#!/bin/bash
# ============================================
# 🚀 Auto Installer: FINAL TINY11 (CODESPACES PERFECTED)
# ============================================

set -e

# Konfigurasi Folder Penyimpanan (Aman dari Reset)
BASE_DIR="$(pwd)/windows_data"
OEM_DIR="$BASE_DIR/oem"
STORAGE_DIR="$BASE_DIR/storage"

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

# ======================================================
# 🧹 BERSIH-BERSIH DISK (WAJIB UTK CODESPACES)
# ======================================================
echo "=== 🧹 MEMBERSIHKAN DISK SPACE ==="
# Hapus cache docker agar muat install Tiny11
docker system prune -a -f --volumes >/dev/null 2>&1 || true

echo "=== 📦 Cek Dependencies ==="
apt-get update -qq -y
apt-get install docker-compose wget curl -qq -y

if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
fi

# ======================================================
# 1️⃣ LOGIKA PINTAR: LANJUTKAN ATAU INSTALL BARU?
# ======================================================
# Cek apakah folder data ada
if [ -d "$BASE_DIR" ] && [ -f "$BASE_DIR/data.img" ]; then
    echo "=== ♻️ DATA LAMA DITEMUKAN! MELANJUTKAN... ==="
    
    # Cek container, jika mati nyalakan, jika hilang buat lagi tapi pakai data lama
    if [ ! "$(docker ps -a -q -f name=windows)" ]; then
         echo "   (Container hilang, membuat ulang wrapper...)"
         EXISTING_INSTALL=false
         # Kita set false agar dia generate yml lagi, tapi data di storage tetap aman
    else
         docker start windows
         EXISTING_INSTALL=true
    fi
else
    echo "=== 🆕 MEMULAI INSTALASI BARU (TINY11)... ==="
    EXISTING_INSTALL=false
    mkdir -p "$OEM_DIR"
    mkdir -p "$STORAGE_DIR"
fi

# ======================================================
# 2️⃣ PERSIAPAN FILE (JIKA INSTALL/RE-CREATE)
# ======================================================
if [ "$EXISTING_INSTALL" = false ]; then

    # --- Download Gambar Profil ---
    echo "   📥 Mengunduh Avatar..."
    wget -q -O "$OEM_DIR/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
    chmod 777 "$OEM_DIR/avatar.jpg"

    # --- SCRIPT INJECTOR (CMD Exit -> Popup) ---
    echo "   📝 Membuat Script System..."

    cat > "$OEM_DIR/install.bat" <<'EOF'
@echo off

:: 1. HAPUS BRANDING DOCKER (Biar Logo Asli Windows)
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\OEMInformation" /f >nul 2>&1
bcdedit /set {current} bootux standard >nul 2>&1

:: 2. PASANG GAMBAR LOCKSCREEN & PROFIL
::    Registry ini memaksa Lockscreen pakai gambar kita
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

:: 3. SCRIPT DESKTOP (CMD MUNCUL -> EXIT -> POPUP)
set "STARTUP_FOLDER=C:\Users\MASTER\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP_FOLDER%" mkdir "%STARTUP_FOLDER%"

(
echo @echo off
echo title WINDOWS ACTIVATION
echo color 0b
echo cls
echo echo ========================================================
echo echo  MENGAKTIFKAN WINDOWS...
echo echo ========================================================
echo.
echo echo 1. Memasang Key...
echo cscript //Nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
echo echo.
echo echo 2. Setting Server KMS...
echo cscript //Nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
echo echo.
echo echo 3. MEMULAI POPUP...
echo echo    CMD akan tertutup. Klik OK pada Popup.
echo.
echo :: Jalankan Popup di proses terpisah
echo start slmgr /ato
echo.
echo :: CMD langsung bunuh diri (Exit)
echo del "%%~f0" ^& exit
) > "%STARTUP_FOLDER%\first_run.bat"

exit
EOF

    # --- DETEKSI KVM ---
    if [ -e /dev/kvm ]; then
        echo "   ✅ KVM Terdeteksi."
        KVM_CONFIG='    devices:
      - /dev/kvm
      - /dev/net/tun'
        ENV_KVM=""
    else
        echo "   ⚠️  KVM TIDAK ADA (Mode Codespaces)."
        KVM_CONFIG='    devices:
      - /dev/net/tun'
        ENV_KVM='      KVM: "N"'
    fi

    # --- DOCKER COMPOSE (TINY11 + SAVER MODE) ---
    cat > windows.yml <<EOF
version: "3.9"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "tiny11"
      USERNAME: "Froxly"
      PASSWORD: "admin@123"
      # 👇 Batas Aman Codespaces
      RAM_SIZE: "7G"
      DISK_SIZE: "25G"
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

    echo "   ▶️  Menjalankan Container..."
    docker-compose -f windows.yml up -d
fi

# ======================================================
# 3️⃣ ANTI ERROR 404 (HEALTH CHECK)
# ======================================================
echo
echo "=== 🔍 Menunggu Windows Siap ==="
RETRIES=0
# Loop sampai port 8006 aktif
while ! curl -s --head --request GET http://localhost:8006 | grep "200 OK" > /dev/null; do
    echo -n "."
    sleep 2
    RETRIES=$((RETRIES+1))
    # Jika instalasi baru, kasih waktu lebih lama
    if [ $RETRIES -gt 60 ] && [ "$EXISTING_INSTALL" = false ]; then
        echo " (Sedang proses install Tiny11... Mohon bersabar)..."
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
echo "🎉 STATUS: ONLINE (FINAL VERSION)"
echo "----------------------------------------------"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "📝 INSTRUKSI:"
echo "   1. Login User: Froxly / admin@123"
echo "   2. Masuk Desktop -> CMD Muncul Sebentar -> Hilang."
echo "   3. Popup 'Product activated' muncul -> Klik OK."
echo "   4. Gambar Profil sudah terpasang."
echo "=============================================="

# ANTI STOP (Keep Alive)
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container mati, menyalakan kembali..."
    docker start windows >/dev/null 2>&1
  fi
  sleep 60
done
