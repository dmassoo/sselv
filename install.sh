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

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip

echo "2. Скачивание официального ядра Xray-core из GitHub..."
rm -f /tmp/xray.zip

# Маскируемся под реальный браузер Chrome на Windows, чтобы обойти защиту GitHub
curl -f -L -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36" \
-o /tmp/xray.zip "https://github.com"

# Создаем системные директории
mkdir -p /usr/local/bin /usr/local/etc/xray

# Распаковываем скачанный архив
unzip -o /tmp/xray.zip -d /usr/local/bin/
rm -f /tmp/xray.zip

# Выставляем права на исполнение бинарника
chmod +x /usr/local/bin/xray

# Отдаем права на папку с конфигурацией вашему пользователю
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "3. Настройка сетевых привилегий для порта 443..."
# Разрешаем бинарнику слушать порт 443 под обычным пользователем
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

# Перезагружаем демона systemd и активируем автозапуск при ребуте
systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
