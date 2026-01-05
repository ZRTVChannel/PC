#!/bin/bash
# ============================================
# 🚀 Auto Installer: WINDOWS 11 (SILENT + FIXED PROFILE)
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
# 1️⃣ SIAPKAN FILE & GAMBAR
# ======================================================
echo
echo "=== 🛠️ MENYIAPKAN FILE SYSTEM ==="
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- Download Gambar Profil ---
# Disimpan sebagai JPG & BMP untuk kompatibilitas penuh
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# ======================================================
# 2️⃣ SCRIPT CMD: SILENT ACTIVATION + FORCE PROFILE
# ======================================================
echo "   📝 Membuat Script Otomatis (install.bat)..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
:: Cek Marker: Jika sudah pernah dijalankan, langsung keluar.
if exist "C:\Users\Public\setup_complete.txt" exit

:: =========================================================
:: BAGIAN 1: FORCE GAMBAR PROFIL (AGAR MUNCUL DI LOGIN SCREEN)
:: =========================================================

:: 1. REGISTRY HACK (WAJIB ADA)
::    Ini memaksa Login Screen membaca file gambar kita, bukan icon default Windows.
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /t REG_DWORD /d 1 /f >nul

:: 2. TIMPA SEMUA GAMBAR DEFAULT
set "SYSDIR=C:\ProgramData\Microsoft\User Account Pictures"
set "SRC=C:\oem\avatar.jpg"

:: Timpa file standar
copy /Y "%SRC%" "%SYSDIR%\user.jpg" >nul
copy /Y "%SRC%" "%SYSDIR%\user.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user.bmp" >nul

:: Timpa file Guest (kadang dipakai default)
copy /Y "%SRC%" "%SYSDIR%\guest.bmp" >nul
copy /Y "%SRC%" "%SYSDIR%\guest.png" >nul

:: Timpa file variasi ukuran (PENTING UNTUK LOGIN SCREEN HD)
copy /Y "%SRC%" "%SYSDIR%\user-32.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-40.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-48.png" >nul
copy /Y "%SRC%" "%SYSDIR%\user-192.png" >nul

:: 3. HAPUS CACHE LAMA
del /F /Q "C:\Users\Public\AccountPictures\*" >nul 2>&1
rmdir /S /Q "C:\Users\Public\AccountPictures" >nul 2>&1


:: =========================================================
:: BAGIAN 2: AKTIVASI SILENT (TANPA POPUP)
:: =========================================================
:: Menggunakan //B (Batch Mode) agar tidak ada pesan "Successfully"

cscript //B //Nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
cscript //B //Nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
cscript //B //Nologo C:\Windows\System32\slmgr /ato

:: Failover ke server lain jika server 1 gagal (tetap silent)
if %errorlevel% NEQ 0 (
    cscript //B //Nologo C:\Windows\System32\slmgr /skms kms.digiboy.ir
    cscript //B //Nologo C:\Windows\System32\slmgr /ato
)

:: =========================================================
:: BAGIAN 3: FINISHING & RESTART
:: =========================================================

:: Buat file penanda agar script tidak jalan lagi setelah restart
echo DONE > "C:\Users\Public\setup_complete.txt"
attrib +h "C:\Users\Public\setup_complete.txt"

:: Restart paksa untuk menerapkan Registry & Gambar
shutdown /r /t 0
exit
EOF

echo "✅ Script Install Siap."

# ======================================================
# 3️⃣ KONFIGURASI DOCKER
# ======================================================
echo "=== 🚀 MENJALANKAN CONTAINER ==="

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
echo "🎉 SELESAI"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "📝 CATATAN PENTING:"
echo "   1. Windows akan booting -> Layar Hitam sebentar (Script jalan)."
echo "   2. Windows akan RESTART OTOMATIS."
echo "   3. Saat menyala kembali, Gambar Profil MASTER sudah terpasang."
echo "   4. Tidak akan ada popup Aktivasi (Silent)."
echo "=============================================="

# ANTI STOP
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Windows sedang Restart... (Normal)"
    sleep 5
  else
    echo "[$(date '+%H:%M:%S')] ✅ Windows Up: ${SECONDS}s"
  fi

  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web: ${CF_WEB}"
  fi
  sleep 60
done
