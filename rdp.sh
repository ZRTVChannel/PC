#!/bin/bash
# ============================================
# 🚀 Auto Installer: FIXED SERVICE & CLEANUP
# ============================================

# Jangan gunakan set -e agar script tidak mati jika ada error kecil
set +e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root."
  exit 1
fi

echo "=== 📦 Update & Install Docker ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y

# --- PERBAIKAN SYSTEMD vs SERVICE ---
echo "=== ⚙️ Menyalakan Docker Service ==="
if pidof dockerd >/dev/null; then
    echo "✅ Docker sudah berjalan."
else
    if command -v systemctl >/dev/null; then
        systemctl start docker
    else
        # Fallback untuk Codespace/Container environment
        service docker start
    fi
fi

# ======================================================
# 1️⃣ BERSIHKAN CONTAINER (DENGAN CARA HALUS)
# ======================================================
echo
echo "=== 🛠️ MEMBERSIHKAN INSTALASI LAMA ==="
# Tambahkan >/dev/null 2>&1 agar error "No such container" tidak muncul di layar
docker stop windows >/dev/null 2>&1
docker rm windows >/dev/null 2>&1
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- Download Gambar Profil ---
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# ======================================================
# 2️⃣ SCRIPT CMD: AMAN & SILENT
# ======================================================
echo "   📝 Membuat Script 'install.bat'..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
if exist "C:\Users\Public\setup_complete.txt" exit

:: 1. FORCE GAMBAR PROFIL
reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /t REG_DWORD /d 1 /f >nul
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
del /F /Q "C:\Users\Public\AccountPictures\*" >nul 2>&1
rmdir /S /Q "C:\Users\Public\AccountPictures" >nul 2>&1

:: 2. AKTIVASI SILENT
cscript //B //Nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
cscript //B //Nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
cscript //B //Nologo C:\Windows\System32\slmgr /ato
if %errorlevel% NEQ 0 (
    cscript //B //Nologo C:\Windows\System32\slmgr /skms kms.digiboy.ir
    cscript //B //Nologo C:\Windows\System32\slmgr /ato
)

:: 3. TANDAI SELESAI (TANPA RESTART OTOMATIS)
echo DONE > "C:\Users\Public\setup_complete.txt"
attrib +h "C:\Users\Public\setup_complete.txt"
exit
EOF

echo "✅ Script Siap."

# ======================================================
# 3️⃣ JALANKAN CONTAINER
# ======================================================
echo "=== 🚀 MENJALANKAN WINDOWS ==="

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
echo "🎉 INSTALASI DIMULAI (VERSI FIX)"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "⚠️  PETUNJUK:"
echo "   1. Windows akan booting normal (Tanpa Error)."
echo "   2. Setelah masuk Desktop, RESTART MANUAL sekali (Start -> Restart)."
echo "   3. Setelah restart manual, Gambar Profil akan muncul."
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
