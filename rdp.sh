#!/bin/bash
# ============================================
# 🚀 Auto Installer: DESKTOP POPUP (SLMGR FIXED)
# ============================================

set -e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

echo "=== 📦 Update & Install Tools ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y

# Fix permissions untuk Codespaces
if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
fi

# ======================================================
# 1️⃣ BERSIHKAN CONTAINER LAMA
# ======================================================
echo
echo "=== 🛠️ MEMBERSIHKAN INSTALASI ==="
docker rm -f windows >/dev/null 2>&1 || true
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- Download Gambar ---
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# ======================================================
# 2️⃣ SCRIPT INJECTOR (LOGIKA SLMGR BARU)
# ======================================================
echo "   📝 Membuat Script System..."

# Script ini jalan di background saat booting
cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off

:: --- BAGIAN 1: PASANG GAMBAR LOCKSCREEN ---
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

:: --- BAGIAN 2: SIAPKAN SCRIPT DESKTOP ---
set "STARTUP_FOLDER=C:\Users\MASTER\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
if not exist "%STARTUP_FOLDER%" mkdir "%STARTUP_FOLDER%"

:: Membuat file first_run.bat
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
echo :: Menggunakan cscript agar output tetap di CMD (Tidak Popup)
echo cscript //Nologo %windir%\system32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
echo echo.
echo echo 2. Setting Server KMS...
echo cscript //Nologo %windir%\system32\slmgr /skms kms8.msguides.com
echo echo.
echo echo 3. MEMULAI AKTIVASI...
echo echo    CMD akan tertutup sekarang.
echo echo    Tunggu Popup 'Windows Script Host' Muncul.
echo.
echo :: Perintah 'start slmgr' akan menjalankan popup terpisah dan CMD langsung exit
echo start slmgr /ato
echo.
echo :: CMD langsung bunuh diri (Exit)
echo del "%%~f0" ^& exit
) > "%STARTUP_FOLDER%\first_run.bat"

exit
EOF

echo "✅ Script Siap."

# ======================================================
# 3️⃣ GENERATE CONFIG (CODESPACES MODE)
# ======================================================
echo "=== ⚙️ DETEKSI HARDWARE ==="

if [ -e /dev/kvm ]; then
    echo "✅ KVM Terdeteksi."
    KVM_CONFIG='    devices:
      - /dev/kvm
      - /dev/net/tun'
    ENV_KVM=""
else
    echo "⚠️  KVM TIDAK ADA (Mode Codespaces)."
    KVM_CONFIG='    devices:
      - /dev/net/tun'
    ENV_KVM='      KVM: "N"'
fi

echo "=== 🚀 MENYIAPKAN FILE DOCKER-COMPOSE ==="

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
      - /tmp/windows-storage:/storage
      - ./oem:/oem
    restart: always
    stop_grace_period: 2m
EOF

# Jalankan Docker
echo "▶️  Menjalankan Container..."
docker-compose -f windows.yml up -d

# ======================================================
# 4️⃣ CLOUDFLARE
# ======================================================
echo "=== ☁️ Start Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

pkill cloudflared || true
nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &

sleep 8
CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)

echo
echo "=============================================="
echo "🎉 INSTALASI SIAP"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "📝 ALUR FINAL:"
echo "   1. Masuk Desktop."
echo "   2. CMD Muncul (Setting Key & Server)."
echo "   3. CMD MATI/HILANG (Auto Exit)."
echo "   4. BARU MUNCUL POPUP 'Product activated'."
echo "   5. Anda Klik OK."
echo "=============================================="

# ANTI STOP
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container mati/restart..."
    docker-compose -f windows.yml up -d >/dev/null 2>&1
  else
    echo "[$(date '+%H:%M:%S')] ✅ Windows Aktif | Up: ${SECONDS}s"
  fi

  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web: ${CF_WEB}"
  fi
  sleep 60
done
