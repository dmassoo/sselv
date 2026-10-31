#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
chmod +x ./start.sh

echo "1. Установка утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Установка оригинального ядра Xray-core (Фикс лимитов)..."
# Скачиваем официальный инсталлятор во временный файл, чтобы избежать ошибки "Argument list too long"
curl -sL https://github.com -o /tmp/xray-install.sh
bash /tmp/xray-install.sh install
rm -f /tmp/xray-install.sh

echo "3. Перенос путей под пользователя $REAL_USER..."
mkdir -p /usr/local/bin /usr/local/etc/xray
ln -sf /usr/bin/xray /usr/local/bin/xray || true

# Отдаем права на конфиги вашему пользователю
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "4. Настройка сетевых привилегий для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/bin/xray || setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "5. Обновление службы systemd под пользователя $REAL_USER..."
sed -i "s/User=xray/User=$REAL_USER/g" /etc/systemd/system/xray.service

# Добавляем привилегии работы с портами без root прав
if ! grep -q "AmbientCapabilities" /etc/systemd/system/xray.service; then
    sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' /etc/systemd/system/xray.service
fi

systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка Xray-core завершена успешно!"
echo "--------------------------------------------------------"
