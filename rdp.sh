#!/bin/bash
# ============================================
# 🚀 Auto Installer: GITHUB CODESPACES EDITION
# ============================================

set -e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root. Jalankan dengan: sudo bash install.sh"
  exit 1
fi

echo "=== 📦 Cek & Install Tools ==="
# Di Codespaces, Docker biasanya sudah ada. Kita cuma butuh docker-compose.
apt-get update -qq -y
apt-get install docker-compose wget -qq -y

# Fix Docker Socket permission (jika perlu)
if [ -e /var/run/docker.sock ]; then
    chmod 666 /var/run/docker.sock
fi

# ======================================================
# 1️⃣ BERSIHKAN CONTAINER LAMA
# ======================================================
echo
echo "=== 🛠️ MEMBERSIHKAN INSTALASI ==="
# Gunakan -f (force) agar tidak protes kalau container tidak ada
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
# 2️⃣ SCRIPT CMD: AMAN (TANPA RESTART)
# ======================================================
echo "   📝 Membuat Script 'install.bat'..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
if exist "C:\Users\Public\setup_complete.txt" exit

:: 1. SETTING GAMBAR PROFIL
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

:: 3. TANDAI SELESAI
echo DONE > "C:\Users\Public\setup_complete.txt"
attrib +h "C:\Users\Public\setup_complete.txt"
exit
EOF

echo "✅ Script Siap."

# ======================================================
# 3️⃣ GENERATE CONFIG (AUTO DETECT KVM)
# ======================================================
echo "=== ⚙️ DETEKSI HARDWARE CODESPACES ==="

# Cek apakah KVM tersedia di Codespace ini
if [ -e /dev/kvm ]; then
    echo "✅ KVM Terdeteksi! Performa Maksimal."
    KVM_CONFIG='    devices:
      - /dev/kvm
      - /dev/net/tun'
    ENV_KVM=""
else
    echo "⚠️  KVM TIDAK TERDETEKSI (Normal di Codespaces)."
    echo "   ➡️  Mengaktifkan Mode Emulasi CPU (Sedikit lebih lambat tapi STABIL)."
    # Kita hapus mapping device /dev/kvm agar tidak error "Host down"
    KVM_CONFIG='    devices:
      - /dev/net/tun'
    # Kita set Environment variable agar image tau kita tidak punya KVM
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

# Jalankan Docker Compose
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
echo "🎉 INSTALASI KHUSUS CODESPACES BERHASIL"
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo "=============================================="
echo "⚠️  CATATAN:"
echo "   1. Karena Codespace tidak punya KVM, Windows mungkin agak lambat."
echo "   2. Error 'Host Down' sudah diperbaiki dengan menghapus /dev/kvm."
echo "   3. Jangan lupa RESTART MANUAL (Start -> Restart) di dalam Windows."
echo "=============================================="

# ANTI STOP (Keep Alive)
SECONDS=0
while true; do
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container mati/restart..."
    # Coba nyalakan lagi kalau mati
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
