#!/bin/bash

set -e
[[ $EUID -ne 0 ]] && { echo "Запускай от root"; exit 1; }

SERVER_CONF="/etc/amnezia/amneziawg/awg0.conf"
[[ ! -f $SERVER_CONF ]] && { echo "ОШИБКА: конфиг сервера не найден"; exit 1; }

# ── Следующий свободный IP ─────────────────────────────────
SERVER_NET=$(grep "^Address" $SERVER_CONF | awk -F= '{print $2}' | tr -d ' ')
BASE_IP=$(echo $SERVER_NET | cut -d. -f1-3)
LAST_IP=$(grep "AllowedIPs" $SERVER_CONF | awk -F= '{print $2}' | tr -d ' ' | cut -d/ -f1 | cut -d. -f4 | sort -n | tail -1)
NEXT_IP=$((LAST_IP + 1))
CLIENT_ADDR="${BASE_IP}.${NEXT_IP}/32"

echo ""
echo "Следующий свободный IP: $CLIENT_ADDR"
read -rp "Имя клиента (пример: phone, laptop): " CLIENT_NAME
read -rp "Использовать IP $CLIENT_ADDR? [Y/n]: " CONFIRM_IP
CONFIRM_IP=${CONFIRM_IP:-y}
if [[ $CONFIRM_IP != "y" && $CONFIRM_IP != "Y" ]]; then
  read -rp "Введи IP вручную (пример: ${BASE_IP}.5/32): " CLIENT_ADDR
fi

# ── Выбор DNS ──────────────────────────────────────────────
echo ""
echo "DNS:"
echo "  1) Cloudflare  — 1.1.1.1, 1.0.0.1"
echo "  2) Google      — 8.8.8.8, 8.8.4.4"
echo "  3) OpenDNS     — 208.67.222.222, 208.67.220.220"
echo "  4) Вручную"
read -rp "Выбор [1-4] (Enter = Cloudflare): " DNS_CHOICE
DNS_CHOICE=${DNS_CHOICE:-1}
case $DNS_CHOICE in
  1) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
  2) CLIENT_DNS="8.8.8.8, 8.8.4.4" ;;
  3) CLIENT_DNS="208.67.222.222, 208.67.220.220" ;;
  4) read -rp "DNS: " CLIENT_DNS ;;
  *) CLIENT_DNS="1.1.1.1, 1.0.0.1" ;;
esac

# ── Ключи ──────────────────────────────────────────────────
CLIENT_PRIVKEY=$(awg genkey)
CLIENT_PUBKEY=$(echo "$CLIENT_PRIVKEY" | awg pubkey)
PRESHARED_KEY=$(awg genpsk)
SERVER_PUBKEY=$(awg show awg0 public-key)
SERVER_IP=$(curl -s -4 ifconfig.me)
PORT=$(grep "^ListenPort" $SERVER_CONF | awk -F= '{print $2}' | tr -d ' ')

# ── MTU из PostUp серверного конфига ──────────────────────
MTU=$(grep "PostUp" $SERVER_CONF | grep -oP 'mtu \K\d+' | head -1)
MTU=${MTU:-1380}

# ── Добавляем peer на сервер ───────────────────────────────
cat >> $SERVER_CONF <<EOF

[Peer]
# $CLIENT_NAME
PublicKey = $CLIENT_PUBKEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_ADDR
EOF

awg set awg0 peer "$CLIENT_PUBKEY" \
  preshared-key <(echo "$PRESHARED_KEY") \
  allowed-ips "$CLIENT_ADDR"

# ── Клиентский конфиг ──────────────────────────────────────
CLIENT_FILE="/root/${CLIENT_NAME}_awg2.conf"
cat > $CLIENT_FILE <<EOF
[Interface]
PrivateKey = $CLIENT_PRIVKEY
Address = $CLIENT_ADDR
DNS = $CLIENT_DNS
MTU = $MTU
$(grep -E "^(Jc|Jmin|Jmax|S1|S2|S3|S4|H1|H2|H3|H4|I1)" $SERVER_CONF)

[Peer]
PublicKey = $SERVER_PUBKEY
PresharedKey = $PRESHARED_KEY
Endpoint = $SERVER_IP:$PORT
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

chmod 600 $CLIENT_FILE

qrencode -t ansiutf8 < $CLIENT_FILE

echo "======================================="
echo "✓ Клиент: $CLIENT_NAME"
echo "✓ IP: $CLIENT_ADDR"
echo "✓ DNS: $CLIENT_DNS"
echo "✓ MTU: $MTU"
echo "✓ Конфиг: $CLIENT_FILE"
echo "======================================="
