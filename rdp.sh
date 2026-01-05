#!/bin/bash
# ============================================
# 🚀 Auto Installer: SAFE MODE (NO FORCED RESTART)
# ============================================

set -e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

echo "=== 📦 Update & Install Docker ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y
systemctl start docker

# ======================================================
# 1️⃣ BERSIHKAN CONTAINER RUSAK & SIAPKAN FILE
# ======================================================
echo
echo "=== 🛠️ MEMBERSIHKAN INSTALASI RUSAK ==="
# Hapus container lama yang error
docker stop windows || true
docker rm windows || true
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- Download Gambar Profil ---
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# ======================================================
# 2️⃣ SCRIPT CMD: AMAN (TANPA RESTART)
# ======================================================
echo "   📝 Membuat Script 'install.bat' (Versi Aman)..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
:: Cek Marker
if exist "C:\Users\Public\setup_complete.txt" exit

:: =========================================================
:: BAGIAN 1: SETTING GAMBAR PROFIL (Hanya Copy, Tidak Restart)
:: =========================================================

:: Registry Hack agar Windows membaca gambar kita
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /t REG_DWORD /d 1 /f >nul

:: Timpa Gambar Default System
set "SYSDIR=C:\ProgramData\Microsoft\User Account Pictures"
set "SRC=C:\oem\avatar.jpg"

copy /Y "%SRC%" "%SYSDIR%\user.jpg" >nul
copy /Y "%SRC%" "%SYSDIR%\user.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-32.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-40.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-48.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-192.png" >nul

:: Hapus Cache
del /F /Q "C:\Users\Public\AccountPictures\*" >nul 2>&1
rmdir /S /Q "C:\Users\Public\AccountPictures" >nul 2>&1

:: =========================================================
:: BAGIAN 2: AKTIVASI SILENT
:: =========================================================
:: Batch Mode (//B) agar tidak ada popup

cscript //B //Nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
cscript //B //Nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
cscript //B //Nologo C:\Windows\System32\slmgr /ato

if %errorlevel% NEQ 0 (
    cscript //B //Nologo C:\Windows\System32\slmgr /skms kms.digiboy.ir
    cscript //B //Nologo C:\Windows\System32\slmgr /ato
)

:: =========================================================
:: BAGIAN 3: FINISHING (JANGAN RESTART)
:: =========================================================

:: Tandai selesai
echo DONE > "C:\Users\Public\setup_complete.txt"
attrib +h "C:\Users\Public\setup_complete.txt"

:: KITA TIDAK MERESTART OTOMATIS DI SINI
:: Agar Windows Setup bisa selesai dengan aman.
exit
EOF

echo "✅ Script Aman Siap."

# ======================================================
# 3️⃣ KONFIGURASI DOCKER
# ======================================================
echo "=== 🚀 MENJALANKAN ULANG CONTAINER ==="

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
echo "🎉 INSTALASI AMAN DIMULAI"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "⚠️  INSTRUKSI PENTING (BACA INI):"
echo "   1. Windows akan booting dengan normal (TIDAK AKAN ERROR LAGI)."
echo "   2. Gambar Profil MUNGKIN BELUM MUNCUL saat pertama kali login."
echo "   3. SETELAH MASUK DESKTOP, silakan RESTART MANUAL sekali:"
echo "      Start -> Power -> Restart."
echo "   4. Setelah restart manual, Gambar Profil dan Aktivasi akan sempurna."
echo "=============================================="

# ANTI STOP
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container windows mati/restart..."
    sleep 5
  else
    echo "[$(date '+%H:%M:%S')] ✅ Windows Aktif | Up: ${SECONDS}s"
  fi

  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web: ${CF_WEB}"
  fi
  sleep 60
done
