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

echo "2. Скачивание и запуск официального инсталлятора XTLS..."
# Качаем скрипт локально, чтобы избежать ошибки 'Argument list too long'
curl -sL https://github.com -o /tmp/xray-install.sh

# Запускаем установку в безопасном режиме, чтобы не оборвать текущий SSH-сеанс
bash /tmp/xray-install.sh install --manually-restart-later
rm -f /tmp/xray-install.sh

echo "3. Настройка прав на конфигурацию согласно спецификации XTLS..."
mkdir -p /usr/local/etc/xray
# Права 0750 на папку коннекта (Владелец root, группа xray может читать)
chown root:xray /usr/local/etc/xray
chmod 0750 /usr/local/etc/xray

# Разрешаем вашему SSH-пользователю (например, vpnadmin) закидывать файлы в эту папку через старт-скрипт
usermod -aG xray $REAL_USER

echo "--------------------------------------------------------"
echo " Установка ядра Xray-core по стандарту XTLS завершена!"
echo " Переходите к запуску: sudo ./start.sh"
echo "--------------------------------------------------------"
