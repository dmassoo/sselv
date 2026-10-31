#!/bin/bash
set -e

# 1. Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

REAL_USER=${SUDO_USER:-$(whoami)}
chmod +x ./start.sh

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Создание официального выделенного пользователя xray..."
if ! id "xray" &>/dev/null; then
    useradd -r -s /bin/false xray
fi

echo "3. Распаковка бинарника и настройка FHS директорий..."
# (Здесь используется локальный архив Xray-linux-64.zip, который вы залили)
if [ ! -f Xray-linux-64.zip ]; then
    echo "Ошибка: Файл Xray-linux-64.zip не найден в папке репозитория!"
    exit 1
fi

mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray
unzip -o Xray-linux-64.zip -d /tmp/xray_unpack
mv -f /tmp/xray_unpack/xray /usr/local/bin/xray
mv -f /tmp/xray_unpack/geoip.dat /usr/local/share/xray/geoip.dat
mv -f /tmp/xray_unpack/geosite.dat /usr/local/share/xray/geosite.dat
rm -rf /tmp/xray_unpack

# Выставляем базовые права на бинарник
chmod 0755 /usr/local/bin/xray
chown root:root /usr/local/bin/xray

# ЖЕЛЕЗОБЕТОННЫЙ ФИКС ПРАВ ДЛЯ ВАШЕГО ПОЛЬЗОВАТЕЛЯ
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray
chmod 0755 /usr/local/etc/xray

chown -R xray:xray /usr/local/share/xray
chmod 0755 /usr/local/share/xray
chmod 0644 /usr/local/share/xray/*.dat

chown xray:xray /var/log/xray
chmod 0700 /var/log/xray

usermod -aG xray $REAL_USER

echo "4. Настройка сетевых привилегий Linux для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "5. Создание официальной службы xray.service под пользователем $REAL_USER..."
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

systemctl daemon-reload
systemctl enable xray

# Удаляем или отключаем старый v2ray, если он остался от прошлых тестов
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

echo "--------------------------------------------------------"
echo " Установка Xray-core успешно завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
