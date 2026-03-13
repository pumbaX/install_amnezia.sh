#!/bin/bash

set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }

echo "=== Обновление системы ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -q
apt-get upgrade -y -q \
  -o Dpkg::Options::="--force-confdef" \
  -o Dpkg::Options::="--force-confold"

echo "=== Зависимости ==="
apt-get install -y -q \
  software-properties-common \
  python3-launchpadlib \
  linux-headers-$(uname -r) \
  net-tools curl git ufw iptables qrencode

echo "=== AmneziaWG PPA ==="
add-apt-repository -y ppa:amnezia/ppa
apt-get update -q
apt-get install -y -q amneziawg amneziawg-tools

echo "=== Проверка модуля ==="
modprobe amneziawg || { echo "ОШИБКА: сделай reboot и запусти снова"; exit 1; }
lsmod | grep -q amneziawg && echo "✓ модуль загружен"

echo "=== IP Forwarding ==="
echo 1 > /proc/sys/net/ipv4/ip_forward
grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || \
  echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p -q

echo "=== Папка конфигов ==="
mkdir -p /etc/amnezia/amneziawg
chmod 700 /etc/amnezia/amneziawg

echo "=== Firewall ==="
ufw allow 22/tcp comment "SSH"   || true
ufw allow 80/tcp comment "HTTP"  || true
ufw allow 443/tcp comment "HTTPS" || true

read -rp "Открыть порт AmneziaWG? [Y/n]: " OPEN_PORT
OPEN_PORT=${OPEN_PORT:-y}
if [[ $OPEN_PORT =~ ^[Yy]$ ]]; then
  read -rp "Порт [51820]: " AWG_PORT
  AWG_PORT=${AWG_PORT:-51820}
  ufw allow "${AWG_PORT}/udp" comment "AmneziaWG" || true
  echo "✓ Порт ${AWG_PORT}/udp открыт"
fi

ufw --force enable || true
ufw status

echo "=== Автозапуск AWG ==="
systemctl enable awg-quick@awg0 2>/dev/null || true
echo "✓ Автозапуск awg-quick@awg0 включён"

echo "======================================="
echo "✓ Установка завершена"
echo "Теперь запускай: ./gen_awg2.sh"
echo "======================================="
