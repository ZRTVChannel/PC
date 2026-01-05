#!/bin/bash
# ============================================
# 🚀 Auto Installer: Windows 11 on Docker + Cloudflare Tunnel
# + Anti Stop/Timeout Protection for Codespaces
# ============================================

set -e

# Fungsi untuk menangani interupsi (CTRL+C)
trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "Script ini butuh akses root. Jalankan dengan: sudo bash install-windows11-cloudflare.sh"
  exit 1
fi

echo
echo "=== 📦 Update & Install Docker Compose ==="
# Menggunakan apt-get dengan opsi quiet untuk mengurangi output spam saat update
apt-get update -qq -y
apt-get install docker-compose -qq -y

systemctl enable docker
systemctl start docker

echo
echo "=== 📂 Membuat direktori kerja dockercom ==="
mkdir -p /root/dockercom
cd /root/dockercom

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
      RAM_SIZE: "8G"
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
    restart: always
    stop_grace_period: 2m
EOF

echo
echo "=== ✅ File windows.yml berhasil dibuat ==="

echo
echo "=== 🚀 Menjalankan Windows 11 container ==="
echo "⏳ Proses ini mungkin memakan waktu lama saat pertama kali (Download ISO)..."
docker-compose -f windows.yml up -d

echo
echo "=== ☁️ Instalasi Cloudflare Tunnel ==="
if [ ! -f "/usr/local/bin/cloudflared" ]; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi

echo
echo "=== 🌍 Membuat tunnel publik untuk akses web & RDP ==="
# Kill cloudflared lama jika ada agar tidak bentrok
pkill cloudflared || true

# Menjalankan tunnel
nohup cloudflared tunnel --url http://localhost:8006 > /var/log/cloudflared_web.log 2>&1 &
nohup cloudflared tunnel --url tcp://localhost:3389 > /var/log/cloudflared_rdp.log 2>&1 &

echo "⏳ Menunggu Cloudflare Tunnel aktif (10 detik)..."
sleep 10

CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
CF_RDP=$(grep -o "tcp://[a-zA-Z0-9.-]*\.trycloudflare\.com:[0-9]*" /var/log/cloudflared_rdp.log | head -n 1)

echo
echo "=============================================="
echo "🎉 Instalasi Selesai!"
echo
if [ -n "$CF_WEB" ]; then
  echo "🌍 Web Console (NoVNC / UI):"
  echo "    ${CF_WEB}"
else
  echo "⚠️ Link Web belum muncul. Coba tunggu beberapa saat dan cek log."
fi

if [ -n "$CF_RDP" ]; then
  echo
  echo "🖥️  Remote Desktop (RDP) Address:"
  echo "    ${CF_RDP}"
else
  echo "⚠️ Link RDP belum muncul. Coba tunggu beberapa saat dan cek log."
fi

echo
echo "🔑 Username: MASTER"
echo "🔒 Password: admin@123"
echo "=============================================="

# ======================================================
# 🛡️ ANTI STOP / TIMEOUT PROTECTION
# ======================================================
echo
echo "=== 🛡️ MENGAKTIFKAN MODE ANTI-STOP CODESPACE 🛡️ ==="
echo "Script ini akan terus berjalan agar environment tidak mati (timeout)."
echo "Jangan tutup terminal ini!"
echo "Edit By Froxlytron"
echo "ENJOY FOR YOU PC"

SECONDS=0
while true; do
  # 1. Menampilkan Heartbeat agar terminal dianggap aktif
  echo "[$(date '+%H:%M:%S')] ✅ System Active | Uptime: ${SECONDS}s"
  
  # 2. Cek apakah container windows masih hidup
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] WARNING: Container Windows mati! Mencoba menyalakan kembali..."
    docker-compose -f windows.yml up -d
  fi

  # 3. Opsional: Cek link cloudflare lagi jika tadi gagal
  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     if [ -n "$CF_WEB" ]; then
        echo "✨ Link Web Baru Ditemukan: ${CF_WEB}"
     fi
  fi

  # Sleep 60 detik agar tidak membanjiri log, tapi cukup untuk mencegah idle disconnect
  sleep 60
done
