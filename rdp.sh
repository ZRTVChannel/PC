#!/bin/bash
# ============================================
# 🚀 Auto Installer: SMART LOOP + REGISTRY MARKER
# ============================================

set -e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

echo
echo "=== 📦 Update & Install Docker ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y
systemctl start docker

# ======================================================
# 1️⃣ PERSIAPAN FILE
# ======================================================
echo
echo "=== 🛠️ TAHAP 1: MENYIAPKAN FILE ==="
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- Download Gambar ---
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# --- BUAT SCRIPT 'SMART LOOP' ---
echo "   📝 Membuat Script install.bat..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
title WINDOWS AUTO SETUP
color 0b

:: --- 1. CEK REGISTRY (APAKAH SUDAH PERNAH SUKSES?) ---
:: Kita cek apakah ada kunci registry khusus yang kita buat sebelumnya
reg query "HKLM\SOFTWARE\AutoSetup" /v Status >nul 2>&1
if %errorlevel% EQU 0 (
    echo [INFO] Setup sudah selesai sebelumnya.
    echo [INFO] Script tidak akan dijalankan lagi.
    exit
)

:: --- 2. LOOPING KONEKSI (SMART WAIT) ---
echo [NET] Menunggu Driver Network Siap...
:NETLOOP
:: Ping gateway Google dengan timeout super cepat (500ms)
ping -n 1 -w 500 8.8.8.8 >nul
if %errorlevel% EQU 0 goto :CONNECTED

:: Jika gagal, jangan diam. Coba flush DNS (biar mancing driver bangun)
ipconfig /flushdns >nul
goto :NETLOOP

:CONNECTED
echo [NET] Terhubung! Melanjutkan Setup...

:: --- 3. PROSES AKTIVASI & GAMBAR ---
echo [SETUP] Memasang Gambar Profil & Aktivasi...

:: Hapus Registry Lock (Biar user bisa ganti foto)
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /f 2>nul

:: Timpa Gambar
set "SYSDIR=C:\ProgramData\Microsoft\User Account Pictures"
set "SRC=C:\oem\avatar.jpg"
copy /Y "%SRC%" "%SYSDIR%\user.jpg" >nul
copy /Y "%SRC%" "%SYSDIR%\user.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.png" >nul

:: Bersihkan Cache
del /F /Q "C:\Users\Public\AccountPictures\*" 2>nul

:: Aktivasi KMS
cscript //nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
cscript //nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
cscript //nologo C:\Windows\System32\slmgr /ato
if %errorlevel% NEQ 0 (
    cscript //nologo C:\Windows\System32\slmgr /skms kms.digiboy.ir
    cscript //nologo C:\Windows\System32\slmgr /ato
)

:: --- 4. TANDAI SELESAI DI REGISTRY & RESTART ---
echo [FINISH] Menulis tanda selesai ke Registry...
:: Membuat folder key baru
reg add "HKLM\SOFTWARE\AutoSetup" /f >nul
:: Menulis status done
reg add "HKLM\SOFTWARE\AutoSetup" /v Status /t REG_SZ /d "Completed" /f >nul

echo.
echo ===========================================
echo ✅ SEMUA SELESAI. RESTARTING WINDOWS...
echo ===========================================
timeout /t 5
shutdown /r /t 0
exit
EOF

echo "✅ Script Smart Loop siap."

# ======================================================
# 2️⃣ JALANKAN WINDOWS
# ======================================================
echo
echo "=== 🚀 TAHAP 2: MENJALANKAN CONTAINER ==="

cat > windows.yml <<'EOF'
version: "3.9"
services:
  windows:
    image: dockurr/windows
    container_name: windows
    environment:
      VERSION: "11"
      USERNAME: "MASTER"
      PASSWORD: "admin@123"
      RAM_SIZE: "16G"
      CPU_CORES: "4"
    devices:
      - /dev/kvm
      - /dev/net/tun
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

docker-compose -f windows.yml up -d

# ======================================================
# 3️⃣ CLOUDFLARE
# ======================================================
echo
echo "=== ☁️ Menjalankan Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

pkill cloudflared || true
nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &

echo "⏳ Menunggu Link..."
sleep 10
CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)

echo
echo "=============================================="
echo "🎉 INSTALASI SELESAI"
echo
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="

# ANTI STOP
echo "🛡️ Monitoring Active..."
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Windows sedang Restart... (Tunggu sebentar)"
    sleep 5
  else
    echo "[$(date '+%H:%M:%S')] ✅ Windows Active | Up: ${SECONDS}s"
  fi

  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web: ${CF_WEB}"
  fi
  sleep 60
done
