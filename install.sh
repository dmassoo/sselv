#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
chmod +x ./start.sh

echo "1. Установка системных утилит и пакета v2ray..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip v2ray

echo "2. Настройка путей и папок конфигурации..."
mkdir -p /usr/local/bin /usr/local/etc/xray

# Создаем символическую ссылку, чтобы система видела v2ray как xray
ln -sf /usr/bin/v2ray /usr/local/bin/xray
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "3. Настройка сетевых привилегий для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/bin/v2ray

echo "4. Регистрация службы в systemd под пользователем $REAL_USER..."
cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray/V2Ray Tunnel Service
After=network.target nss-lookup.target

[Service]
User=$REAL_USER
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Отключаем стандартную службу v2ray, так как мы создали свою кастомную
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
