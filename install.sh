#!/bin/bash
set -e

# 1. Проверка на root-права
if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

# Получаем имя вашего SSH-пользователя (например, vpnadmin)
REAL_USER=${SUDO_USER:-$(whoami)}

# Принудительно делаем исполняемым соседний файл на будущее
chmod +x ./start.sh

echo "1. Установка базовых утилит и Snapd..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip snapd

echo "2. Установка ядра Xray-core из Snap Store..."
# Snap использует свои независимые CDN каналы в Европе, которые скачают рабочий бинарник без ошибок
snap install xray-core

# Создаем системные директории и делаем симлинк на snap-версию бинарника
mkdir -p /usr/local/bin /usr/local/etc/xray
ln -sf /snap/bin/xray-core /usr/local/bin/xray

# Отдаем права на папку с конфигурацией вашему пользователю
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "3. Настройка сетевых привилегий для порта 443..."
# Разрешаем snap-бинарнику слушать порт 443 под обычным пользователем
setcap 'cap_net_bind_service=ep' /snap/bin/xray-core || true

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

# Удаляем или отключаем старый v2ray, если он остался от прошлых тестов
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true

# Перезагружаем демона systemd и активируем автозапуск при ребуте
systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
