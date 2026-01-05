#!/bin/bash
# ============================================
# 🚀 Auto Installer: Win 11 + INJECTED ACTIVATION
# ============================================

set -e

trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "Script ini butuh akses root. Jalankan dengan: sudo bash install.sh"
  exit 1
fi

echo
echo "=== 📦 Update & Install Docker Compose ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y

systemctl enable docker
systemctl start docker

echo
echo "=== 📂 Menyiapkan Folder Kerja & Injection ==="
mkdir -p /root/dockercom/oem
mkdir -p /tmp/windows-storage
cd /root/dockercom

# ======================================================
# 🖼️ DOWNLOAD GAMBAR PROFIL
# ======================================================
echo "=== 🖼️ Menyiapkan Gambar Profil ==="
PROFILE_IMG="/tmp/windows-storage/avatar.jpg"
if [ ! -f "$PROFILE_IMG" ]; then
  wget -q -O "$PROFILE_IMG" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
  chmod 777 "$PROFILE_IMG"
fi

# ======================================================
# 💉 MENYIAPKAN SCRIPT AKTIVASI (INJECTION)
# ======================================================
# Script ini dibuat SEBELUM Windows jalan.
# Nanti Windows akan menjalankannya otomatis via folder /oem
echo "=== 💉 Membuat Script Injector Aktivasi (install.bat) ==="

cat > /root/dockercom/oem/install.bat <<'EOF'
@echo off
title SYSTEM PREPARATION & ACTIVATION
color 0b

:: 1. Tunggu Internet Stabil (Looping sampai connect)
:WAIT_NET
echo [INFO] Memeriksa koneksi internet...
ping 8.8.8.8 -n 1 >nul
if errorlevel 1 (
    echo [WAIT] Internet belum siap. Menunggu 5 detik...
    timeout /t 5 >nul
    goto WAIT_NET
)
echo [OK] Internet Terhubung!

:: 2. Proses Aktivasi KMS
echo [EXEC] Memasang Key Windows 11 Pro...
cscript //nologo %windir%\system32\slmgr /ipk W269N-WFGWX-YVC9B-4J6C9-T835GX

echo [EXEC] Mengatur Server KMS...
cscript //nologo %windir%\system32\slmgr /skms kms8.msguides.com

echo [EXEC] Memicu Aktivasi Online...
cscript //nologo %windir%\system32\slmgr /ato

:: 3. Mengatur Gambar Profil (Optional - Copy ke sistem)
if exist "C:\storage\avatar.jpg" (
    echo [INFO] Menyalin gambar profil...
    copy "C:\storage\avatar.jpg" "C:\ProgramData\Microsoft\User Account Pictures\user.jpg" /Y
    copy "C:\storage\avatar.jpg" "C:\ProgramData\Microsoft\User Account Pictures\guest.jpg" /Y
    copy "C:\storage\avatar.jpg" "C:\ProgramData\Microsoft\User Account Pictures\admin.jpg" /Y
)

echo [DONE] Aktivasi & Setup Selesai.
exit
EOF

echo "✅ Script aktivasi berhasil dibuat di folder OEM."

# ======================================================
# 🏗️ KONFIGURASI DOCKER
# ======================================================
echo
echo "=== 🧾 Membuat file windows.yml ==="
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
      # 👇 INI KUNCINYA: Folder oem di-mount agar script di atas terbaca Windows
      - ./oem:/oem
    restart: always
    stop_grace_period: 2m
EOF

echo
echo "=== 🚀 Menjalankan Instalasi Windows ==="
echo "   Script aktivasi sudah disuntikkan. Windows akan aktif sendiri setelah booting."
docker-compose -f windows.yml up -d

echo
echo "=== ☁️ Menjalankan Cloudflare Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

pkill cloudflared || true
nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &

echo "⏳ Menunggu Cloudflare Tunnel aktif (10 detik)..."
sleep 10

CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
CF_RDP=$(grep -o "tcp://[a-zA-Z0-9.-]*\.trycloudflare\.com:[0-9]*" /var/log/cloudflared_rdp.log | head -n 1)

echo
echo "=============================================="
echo "🎉 Instalasi & Injection Script Selesai!"
echo
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console: ${CF_WEB}"
fi
if [ -n "$CF_RDP" ]; then
  echo "🖥️  RDP Address: ${CF_RDP}"
fi
echo
echo "ℹ️  CATATAN PENTING:"
echo "    1. Windows akan booting."
echo "    2. Script 'install.bat' yang kita buat tadi otomatis jalan di dalam Windows."
echo "    3. Tunggu sekitar 2-3 menit setelah masuk desktop agar status menjadi 'Activated'."
echo "=============================================="

# ======================================================
# 🛡️ ANTI STOP PROTECTION
# ======================================================
echo "=== 🛡️ MODE ANTI-STOP AKTIF ==="
SECONDS=0
while true; do
  echo "[$(date '+%H:%M:%S')] ✅ System Active | Uptime: ${SECONDS}s"
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Restarting container..."
    docker-compose -f windows.yml up -d
  fi
  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web Baru: ${CF_WEB}"
  fi
  sleep 60
done
