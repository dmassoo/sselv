#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

# 1. Железобетонно определяем имя вашего реального SSH-пользователя
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER=$(who am i | awk '{print $1}')
fi
if [ -z "$REAL_USER" ]; then
    REAL_USER="vpnadmin" # Резервный вариант
fi

# Сразу делаем исполняемым start.sh
chmod +x ./start.sh

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Создание официальной группы и системного пользователя xray..."
if ! getent group xray >/dev/null; then
    groupadd -r xray
fi
if ! id "xray" &>/dev/null; then
    useradd -r -s /bin/false -g xray xray
fi

# ДОБАВЛЯЕМ ВАС В ГРУППУ XRAY (чтобы работал cat без sudo)
usermod -aG xray "$REAL_USER"

echo "3. Распаковка локального архива Xray-core..."
if [ ! -f Xray-linux-64.zip ]; then
    echo "Ошибка: Положите файл Xray-linux-64.zip в папку репозитория!"
    exit 1
fi

mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray
unzip -o Xray-linux-64.zip -d /tmp/xray_unpack
mv -f /tmp/xray_unpack/xray /usr/local/bin/xray
mv -f /tmp/xray_unpack/geoip.dat /usr/local/share/xray/geoip.dat
mv -f /tmp/xray_unpack/geosite.dat /usr/local/share/xray/geosite.dat
rm -rf /tmp/xray_unpack

# Настройка прав на бинарник
chmod 0755 /usr/local/bin/xray
chown root:root /usr/local/bin/xray

# НАСТРОЙКА ДИРЕКТОРИИ КОНФИГУРАЦИИ (Владелец root, группа xray имеет полный доступ)
chown root:xray /usr/local/etc/xray
chmod 0775 /usr/local/etc/xray

# Настройка прав на базы данных и логи
chown -R xray:xray /usr/local/share/xray /var/log/xray
chmod 0755 /usr/local/share/xray
chmod 0644 /usr/local/share/xray/*.dat
chmod 0700 /var/log/xray

echo "4. Настройка сетевых привилегий Linux для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "5. Создание официальной службы xray.service под пользователем XRAY..."
cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com
After=network.target nss-lookup.target

[Service]
User=xray
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

# Чистим старый v2ray, если остался
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

echo "--------------------------------------------------------"
echo " Системная установка выполнена! Права настроены."
echo " Перезапустите SSH-сессию (выход и вход), чтобы обновились ваши группы,"
echo " после чего запустите генерацию: sudo ./start.sh"
echo "--------------------------------------------------------"
