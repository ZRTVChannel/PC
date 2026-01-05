#!/bin/bash
# ============================================
# 🚀 Auto Installer: PERSISTENT + ANTI 404 + CMD TRICK
# ============================================

set -e

# Folder Penyimpanan (JANGAN DI /tmp/ AGAR TIDAK HILANG)
BASE_DIR="$(pwd)/windows_data"
OEM_DIR="$BASE_DIR/oem"
STORAGE_DIR="$BASE_DIR/storage"

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

echo "=== 📦 Cek Dependencies ==="
apt-get update -qq -y
apt-get install docker-compose wget curl -qq -y

# Fix permissions
if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
fi

# ======================================================
# 1️⃣ LOGIKA PINTAR: LANJUTKAN ATAU INSTALL BARU?
# ======================================================
echo
if [ "$(docker ps -a -q -f name=windows)" ]; then
    echo "=== ♻️ WINDOWS SUDAH ADA! MELANJUTKAN... ==="
    echo "   Tidak perlu install ulang. Menyalakan container..."
    docker start windows
    echo "✅ Windows dinyalakan."
    
    # Skip langkah instalasi, langsung ke Cloudflare
    EXISTING_INSTALL=true
else
    echo "=== 🆕 BELUM ADA WINDOWS. MEMULAI INSTALASI BARU... ==="
    EXISTING_INSTALL=false
    
    # Buat folder penyimpanan persisten
    mkdir -p "$OEM_DIR"
    mkdir -p "$STORAGE_DIR"
fi

# ======================================================
# 2️⃣ JIKA INSTALL BARU: SIAPKAN FILE & SCRIPT
# ======================================================
if [ "$EXISTING_INSTALL" = false ]; then

    # --- Download Gambar ---
    echo "   📥 Mengunduh Avatar..."
    wget -q -O "$OEM_DIR/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
    chmod 777 "$OEM_DIR/avatar.jpg"

    # --- SCRIPT INJECTOR (CMD Exit -> Popup) ---
    echo "   📝 Membuat Script System..."

    cat > "$OEM_DIR/install.bat" <<'EOF'
@echo off

:: --- PASANG GAMBAR LOCKSCREEN ---
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /t REG_DWORD /d 1 /f >nul
set "SYSDIR=C:\ProgramData\Microsoft\User Account Pictures"
set "SRC=C:\oem\avatar.jpg"

copy /Y "%SRC%" "%SYSDIR%\user.jpg" >nul
copy /Y "%SRC%" "%SYSDIR%\user.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-192.png" >nul

del /F /Q "C:\Users\Public\AccountPictures\*" >nul 2>&1
rmdir /S /Q "C:\Users\Public\AccountPictures" >nul 2>&1

:: --- SIAPKAN SCRIPT DESKTOP ---
set "STARTUP_FOLDER=C:\Users\MASTER\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP_FOLDER%" mkdir "%STARTUP_FOLDER%"

:: Script: CMD Muncul -> Exit -> Popup Muncul
(
echo @echo off
echo title WINDOWS ACTIVATION
echo color 0b
echo cls
echo echo ========================================================
echo echo  SEDANG MENGAKTIFKAN WINDOWS...
echo echo  Tunggu sebentar...
echo echo ========================================================
echo echo.
echo echo 1. Memasang Key...
echo cscript //Nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
echo echo.
echo echo 2. Setting Server KMS...
echo cscript //Nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
echo echo.
echo echo 3. MEMULAI POPUP...
echo echo    CMD akan tertutup sekarang.
echo echo    Tunggu Popup 'Windows Script Host' Muncul, lalu KLIK OK.
echo.
echo start slmgr /ato
echo.
echo del "%%~f0" ^& exit
) > "%STARTUP_FOLDER%\first_run.bat"

exit
EOF

    # --- DETEKSI KVM (Hardware) ---
    echo "   ⚙️ Konfigurasi Docker..."
    if [ -e /dev/kvm ]; then
        echo "      ✅ KVM Terdeteksi."
        KVM_CONFIG='    devices:
      - /dev/kvm
      - /dev/net/tun'
        ENV_KVM=""
    else
        echo "      ⚠️  KVM TIDAK ADA (Mode Codespaces)."
        KVM_CONFIG='    devices:
      - /dev/net/tun'
        ENV_KVM='      KVM: "N"'
    fi

    # --- BUAT DOCKER COMPOSE ---
    cat > windows.yml <<EOF
version: "3.9"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "7G"
      CPU_CORES: "4"
${ENV_KVM}
${KVM_CONFIG}
    cap_add:
      - NET_ADMIN
    ports:
      - "8006:8006"
      - "3389:3389/tcp"
      - "3389:3389/udp"
    volumes:
      - $STORAGE_DIR:/storage
      - $OEM_DIR:/oem
    restart: always
    stop_grace_period: 2m
EOF

    echo "   ▶️  Menjalankan Instalasi Baru..."
    docker-compose -f windows.yml up -d
fi

# ======================================================
# 3️⃣ ANTI ERROR 404 (HEALTH CHECK)
# ======================================================
echo
echo "=== 🔍 Memeriksa Kesehatan Container ==="
echo "   ⏳ Menunggu Layanan Web Windows (Port 8006) siap..."
echo "      (Ini mencegah Error 404 pada Cloudflare)"

# Loop menunggu sampai port 8006 merespon HTTP 200 OK
RETRIES=0
while ! curl -s --head --request GET http://localhost:8006 | grep "200 OK" > /dev/null; do
    echo -n "."
    sleep 2
    RETRIES=$((RETRIES+1))
    
    # Jika sudah 60 detik (30x2) belum nyala, mungkin booting awal
    if [ $RETRIES -gt 30 ] && [ "$EXISTING_INSTALL" = false ]; then
        echo " (Sedang proses instalasi awal, mohon bersabar)..."
        RETRIES=0
    fi
done
echo
echo "✅ Windows Web Service SIAP!"

# ======================================================
# 4️⃣ CLOUDFLARE TUNNEL
# ======================================================
echo "=== ☁️ Start Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

pkill cloudflared || true
nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &

sleep 5
CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)

echo
echo "=============================================="
echo "🎉 STATUS: ONLINE"
if [ "$EXISTING_INSTALL" = true ]; then
    echo "♻️  Mode: MELANJUTKAN SESI SEBELUMNYA"
else
    echo "🆕  Mode: INSTALASI BARU"
fi
echo "----------------------------------------------"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="

if [ "$EXISTING_INSTALL" = false ]; then
    echo "  EDIT BY FROXLYTRON "
    echo "   ENJOY FOR YOU PC "
    echo "   UNTUK BUAT KAMU "
fi

# ANTI STOP
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container mati/restart. Menghidupkan kembali..."
    docker start windows >/dev/null 2>&1
  fi
  sleep 60
done
