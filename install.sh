#!/bin/bash
set -e

# 1. Проверка на root-права (sudo необходим для apt и systemd)
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

# Получаем имя пользователя, который вызвал sudo (ваш SSH-юзер)
REAL_USER=${SUDO_USER:-$(whoami)}
REAL_HOMEDIR=$(eval echo ~$REAL_USER)

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Скачивание официального ядра Xray-core из GitHub..."
curl -L -o /tmp/xray.zip https://github.com
mkdir -p /usr/local/bin /usr/local/etc/xray
unzip -o /tmp/xray.zip -d /usr/local/bin/
rm -f /tmp/xray.zip

chmod +x /usr/local/bin/xray

# Назначаем владельцем папки конфигурации вашего пользователя
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "3. Настройка сетевых привилегий для работы на порту 443..."
# Позволяет бинарнику слушать порт 443 без прав root
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "4. Регистрация службы Xray в systemd под пользователем $REAL_USER..."
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

# Перезагружаем демона systemd и включаем автозапуск службы при ребуте
systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
