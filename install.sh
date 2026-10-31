#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
  echo "Ошибка: Запустите скрипт через sudo: sudo ./install.sh"
  exit 1
fi

echo "1. Установка системных утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git

echo "2. Установка официального ядра Xray и службы systemd..."
bash -c "$(curl -L https://github.com)" @ install

chmod +x ./start.sh

echo "--------------------------------------------------------"
echo " Базовая установка завершена успешно!"
echo " Создайте .env и запустите: sudo ./start.sh"
echo "--------------------------------------------------------"
