#!/bin/bash
# ============================================
# 🚀 Auto Installer: Windows 11 + Cloudflare + Anti-Stop
# + Auto Download Profile Picture
# ============================================

set -e

# Fungsi untuk menangani interupsi (CTRL+C)
trap 'echo "🛑 Menghentikan script..."; exit 0' SIGINT SIGTERM

echo "=== 🔧 Menjalankan sebagai root ==="
if [ "$EUID" -ne 0 ]; then
  echo "Script ini butuh akses root. Jalankan dengan: sudo bash install-windows11.sh"
  exit 1
fi

echo
echo "=== 📦 Update & Install Docker Compose ==="
apt-get update -qq -y
apt-get install docker-compose wget -qq -y

systemctl enable docker
systemctl start docker

echo
echo "=== 📂 Membuat direktori kerja & Storage ==="
mkdir -p /root/dockercom
mkdir -p /tmp/windows-storage
cd /root/dockercom

# ======================================================
# 🖼️ DOWNLOAD USER PROFILE PICTURE (SEKALI)
# ======================================================
echo
echo "=== 🖼️ Menyiapkan Gambar Profil User ==="
PROFILE_IMG="/tmp/windows-storage/avatar.jpg"

# Cek jika gambar belum ada, baru download (Supaya cuma "sekali")
if [ ! -f "$PROFILE_IMG" ]; then
  echo "📥 Mengunduh gambar profil keren..."
  # URL gambar profil (Bisa diganti link gambar lain jika mau)
  wget -q -O "$PROFILE_IMG" "https://i.pinimg.com/736x/b8/c6/b3/b8c6b3bfba03883bc4fd243d0e80a8a3.jpg"
  chmod 777 "$PROFILE_IMG"
  echo "✅ Gambar profil tersimpan di: $PROFILE_IMG"
  echo "ℹ️  Nanti di Windows, cari file ini di drive Storage untuk dijadikan profil."
else
  echo "✅ Gambar profil sudah ada, melewati unduhan."
fi

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
      # Mapping folder host yang berisi gambar profil ke dalam windows
      - /tmp/windows-storage:/storage
    restart: always
    stop_grace_period: 2m
EOF

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
echo "=== 🌍 Membuat tunnel publik ==="
pkill cloudflared || true

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
  echo "🌍 Web Console (NoVNC):"
  echo "    ${CF_WEB}"
else
  echo "⚠️ Link Web belum muncul. Tunggu sebentar..."
fi

if [ -n "$CF_RDP" ]; then
  echo "🖥️  RDP Address:"
  echo "    ${CF_RDP}"
fi
echo
echo "🔑 User: Admin | Pass: admin@123"
echo "🖼️  Gambar Profil: Tersedia di folder 'storage' di dalam Windows"
echo "=============================================="

# ======================================================
# 🛡️ ANTI STOP / TIMEOUT PROTECTION
# ======================================================
echo
echo "=== 🛡️ MENGAKTIFKAN MODE ANTI-STOP ==="
echo "Script ini berjalan loop agar Codespace tidak mati."
echo "JANGAN TUTUP TERMINAL INI."
echo "Edit By Froxlytron"
echo "ENJOY FOR YOU PC!"
echo "UNTUK BUAT KAMU!"

SECONDS=0
while true; do
  echo "[$(date '+%H:%M:%S')] ✅ System Active | Uptime: ${SECONDS}s"
  
  # Cek container, nyalakan jika mati
  if [ -z "$(docker ps -q -f name=windows)" ]; then
    echo "[!] Container Windows mati! Restarting..."
    docker-compose -f windows.yml up -d
  fi

  # Coba ambil link lagi jika tadi kosong
  if [ -z "$CF_WEB" ]; then
     CF_WEB=$(grep -o "https://[a-zA-Z0-9.-]*\.trycloudflare\.com" /var/log/cloudflared_web.log | head -n 1)
     [ -n "$CF_WEB" ] && echo "✨ Link Web Baru: ${CF_WEB}"
  fi

  sleep 60
done
