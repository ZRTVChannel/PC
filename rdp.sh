#!/bin/bash
# ============================================
# 🚀 Auto Installer: Win 11 + AUTO RESTART AFTER SETUP
# ============================================

set -e

# Trap Anti-Stop
trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "❌ Butuh akses root. Jalankan dengan: sudo bash install.sh"
  exit 1
fi

echo
echo "=== 📦 Update & Install Docker ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y
systemctl start docker

# ======================================================
# 1️⃣ PERSIAPAN FILE (PRE-BOOT)
# ======================================================
echo
echo "=== 🛠️ TAHAP 1: MENYIAPKAN LOGIKA AUTO-RESTART ==="
rm -rf /root/dockercom
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# --- A. Download Gambar Profil ---
echo "   📥 Mengunduh Avatar..."
wget -q -O "/root/dockercom/oem/avatar.jpg" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
chmod 777 "/root/dockercom/oem/avatar.jpg"

# --- B. Buat Script CMD Cerdas (Marker Logic) ---
echo "   📝 Membuat Script 'install.bat' dengan Auto-Restart..."

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
title WINDOWS SETUP AUTOMATION
color 0b

:: --- CEK APAKAH INI BOOT PERTAMA ATAU KEDUA ---
if exist "C:\setup_done.marker" goto :ALREADY_DONE

:: ==========================================
:: JIKA INI BOOT PERTAMA (SETUP & AKTIVASI)
:: ==========================================
echo [INIT] Boot Pertama Terdeteksi. Memulai Setup...

:: 1. GANTI GAMBAR PROFIL DEFAULT (Sistem Level)
echo [IMG] Mengganti Default System Images...
set "SYSDIR=C:\ProgramData\Microsoft\User Account Pictures"
set "SRC=C:\oem\avatar.jpg"

:: Hapus registry lock (agar user bisa ganti foto nanti)
reg delete "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\Explorer" /v UseDefaultTile /f 2>nul

:: Timpa gambar default
copy /Y "%SRC%" "%SYSDIR%\user.jpg"
copy /Y "%SRC%" "%SYSDIR%\user.png"
copy /Y "%SRC%" "%SYSDIR%\user.bmp"
copy /Y "%SRC%" "%SYSDIR%\guest.bmp"
copy /Y "%SRC%" "%SYSDIR%\guest.png"
copy /Y "%SRC%" "%SYSDIR%\user-32.png"
copy /Y "%SRC%" "%SYSDIR%\user-40.png"
copy /Y "%SRC%" "%SYSDIR%\user-48.png"
copy /Y "%SRC%" "%SYSDIR%\user-192.png"

:: Hapus Cache Gambar Lama
del /F /Q "C:\Users\Public\AccountPictures\*" 2>nul

:: 2. AKTIVASI WINDOWS (KMS)
echo [ACT] Menunggu koneksi internet...
:NETLOOP
ping 8.8.8.8 -n 1 >nul
if errorlevel 1 (
    timeout /t 2 >nul
    goto NETLOOP
)

echo [ACT] Memasang Key Windows 11 Pro...
cscript //nologo C:\Windows\System32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX
echo [ACT] Mencoba Aktivasi...
cscript //nologo C:\Windows\System32\slmgr /skms kms8.msguides.com
cscript //nologo C:\Windows\System32\slmgr /ato
if %errorlevel% NEQ 0 (
    cscript //nologo C:\Windows\System32\slmgr /skms kms.digiboy.ir
    cscript //nologo C:\Windows\System32\slmgr /ato
)

:: 3. BUAT TANDA & RESTART
echo [FINISH] Setup Selesai! Menandai sistem...
echo SETUP COMPLETED > "C:\setup_done.marker"

echo [RESTART] Windows akan Restart dalam 10 detik untuk menerapkan perubahan...
timeout /t 10
shutdown /r /t 0
exit

:: ==========================================
:: JIKA INI BOOT KEDUA (SUDAH SELESAI)
:: ==========================================
:ALREADY_DONE
echo [INFO] Setup sebelumnya sudah selesai.
echo [INFO] Welcome to Windows 11!
exit
EOF

echo "✅ Script Auto-Restart berhasil dibuat."

# ======================================================
# 2️⃣ MENJALANKAN DOCKER
# ======================================================
echo
echo "=== 🚀 TAHAP 2: MENJALANKAN WINDOWS ==="

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
    # PENTING: restart always agar saat Windows reboot, container hidup lagi
    restart: always
    stop_grace_period: 2m
EOF

docker-compose -f windows.yml up -d

# ======================================================
# 3️⃣ CLOUDFLARE & MONITORING
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

echo "⏳ Menunggu Link Cloudflare..."
sleep 10
CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)

echo
echo "=============================================="
echo "🎉 INSTALASI SELESAI"
echo
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
echo
echo "⚠️  PERHATIAN (JANGAN KAGET):"
echo "   1. Windows akan booting pertama kali."
echo "   2. Melakukan Aktivasi & Ganti Foto."
echo "   3. WINDOWS AKAN MATI/RESTART SENDIRI (Sekitar menit ke-3 atau ke-4)."
echo "   4. Web Console mungkin akan disconnect sebentar."
echo "   5. Refresh browser, Windows akan nyala kembali dengan Foto Profil yg benar."
echo "=============================================="

# ANTI STOP & MONITORING
echo "🛡️ System Monitoring Active..."
SECONDS=0
while true; do
  # Cek apakah container windows hidup
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Windows sedang restart/mati. Menunggu naik kembali..."
    # Kita tidak paksa 'docker-compose up' disini karena 'restart: always'
    # di YAML sudah menangani reboot dari dalam VM.
    # Kita hanya menunggu.
    sleep 5
  else
    echo "[$(date '+%H:%M:%S')] ✅ Windows Active | Up: ${SECONDS}s"
  fi

  # Cek Cloudflare Link (Re-print jika hilang)
  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web (Refresh jika perlu): ${CF_WEB}"
  fi
  
  sleep 60
done
