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

echo "2. Установка официального ядра Xray..."
# Скачиваем и запускаем официальный инсталлятор через правильный синтаксис
curl -L https://github.com | bash -s -- install

echo "3. Настройка прав и перенос службы на пользователя $REAL_USER..."
# Даем права на папки конфигурации вашему пользователю
mkdir -p /usr/local/etc/xray
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

# Модифицируем созданную инсталлятором службу systemd под вашего пользователя
SED_USER_REPLACE="s/User=xray/User=$REAL_USER/g"
sed -i "$SED_USER_REPLACE" /etc/systemd/system/xray.service

# Добавляем в службу необходимые сетевые привилегии, чтобы работать под обычным пользователем
if ! grep -q "AmbientCapabilities" /etc/systemd/system/xray.service; then
    sed -i '/\[Service\]/a AmbientCapabilities=CAP_NET_BIND_SERVICE\nCapabilityBoundingSet=CAP_NET_BIND_SERVICE' /etc/systemd/system/xray.service
fi

# Перезагружаем демона systemd и включаем автозапуск службы при ребуте
systemctl daemon-reload
systemctl enable xray

echo "--------------------------------------------------------"
echo " Установка успешно завершена под пользователем: $REAL_USER"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
