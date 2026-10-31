#!/bin/bash
set -e

# 1. Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
chmod +x ./start.sh

echo "1. Установка базовых утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip software-properties-common

echo "2. Добавление официального репозитория Xray..."
# Добавляем официальный PPA репозиторий XTLS, который поддерживается серверами Ubuntu
add-apt-repository -y ppa:izgharii/xray || true
apt-get update

echo "3. Установка ядра xray..."
# Устанавливаем официальный пакет xray-core
apt-get install -y xray || apt-get install -y xray-core

# Проверяем, куда встал бинарник, и делаем правильную ссылку для start.sh
mkdir -p /usr/local/bin /usr/local/etc/xray
if [ -f /usr/bin/xray ]; then
    ln -sf /usr/bin/xray /usr/local/bin/xray
elif [ -f /usr/bin/xray-core ]; then
    ln -sf /usr/bin/xray-core /usr/local/bin/xray
fi

# Отдаем права вашему пользователю
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "4. Настройка сетевых привилегий для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "5. Регистрация службы Xray в systemd под пользователем $REAL_USER..."
cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com
After=network.target nss-lookup.target

[Service]
User=$REAL_USER
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
AmbientCapabilities=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
ExecStart=/usr/local/bin/xray run -config /usr/local/etc/xray/config.json
Restart=on-failure
RestartPreventExitStatus=23
LimitNPROC=10000
LimitNOFILE=1000000

[Install]
WantedBy=multi-user.target
EOF

# Останавливаем дефолтный v2ray (если он запустился) и включаем xray
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена!"
echo " Теперь запускайте настройку конфигурации: sudo ./start.sh"
echo "--------------------------------------------------------"
