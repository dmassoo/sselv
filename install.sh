#!/bin/bash
set -e

# 1. Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

# Железобетонно определяем имя реального SSH-пользователя
REAL_USER=${SUDO_USER:-$(logname 2>/dev/null)}
if [ -z "$REAL_USER" ] || [ "$REAL_USER" = "root" ]; then
    REAL_USER=$(who am i | awk '{print $1}')
fi
if [ -z "$REAL_USER" ]; then
    REAL_USER="vpnadmin" # Резервное имя, если интерактивная сессия скрыта
fi

# Принудительно делаем исполняемым соседний файл на будущее
chmod +x ./start.sh

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Создание официальной группы и пользователя xray..."
if ! getent group xray >/dev/null; then
    groupadd -r xray
fi
if ! id "xray" &>/dev/null; then
    useradd -r -s /bin/false -g xray xray
fi

# Добавляем вашего SSH-пользователя в группу xray для совместного доступа к конфигам
usermod -aG xray "$REAL_USER"

echo "3. Распаковка бинарника и настройка FHS директорий..."
if [ ! -f Xray-linux-64.zip ]; then
    echo "Ошибка: Файл Xray-linux-64.zip не найден в текущей директории!"
    echo "Пожалуйста, скачайте его на ПК и запуште в Git."
    exit 1
fi

mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray
unzip -o Xray-linux-64.zip -d /tmp/xray_unpack
mv -f /tmp/xray_unpack/xray /usr/local/bin/xray
mv -f /tmp/xray_unpack/geoip.dat /usr/local/share/xray/geoip.dat
mv -f /tmp/xray_unpack/geosite.dat /usr/local/share/xray/geosite.dat
rm -rf /tmp/xray_unpack

# Выставляем базовые права на исполняемый файл
chmod 0755 /usr/local/bin/xray
chown root:root /usr/local/bin/xray

# НАСТРОЙКА СОВМЕСТНЫХ ПРАВ (Ваш юзер управляет, xray читает)
chown -R root:xray /usr/local/etc/xray
chmod 0775 /usr/local/etc/xray

chown -R xray:xray /usr/local/share/xray
chmod 0755 /usr/local/share/xray
chmod 0644 /usr/local/share/xray/*.dat

chown xray:xray /var/log/xray
chmod 0700 /var/log/xray

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

# Очищаем систему от старых конфликтующих служб v2ray
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена для пользователя: $REAL_USER"
echo " Чтобы применились группы, сессия обновится автоматически."
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"

# Принудительно обновляем группы в текущем окружении, чтобы не делать логаут руками
exec sg xray "$0_apply_done" 2>/dev/null || true
