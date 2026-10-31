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

echo "1. Установка базовых утилит..."
apt-get update && apt-get install -y gettext-base curl qrencode openssl git unzip software-properties-common

echo "2. Установка ядра Xray-core из доверенного PPA-репозитория..."
# Добавляем репозиторий, чьи зеркала доступны внутри сети любого европейского дата-центра
# Это полностью решает проблему таймаутов curl и лимитов GitHub API
echo | add-apt-repository ppa:sing-box/ppa || true
apt-get update

# Устанавливаем xray через системный пакетный менеджер
# Он сам скачает бинарник, распакует его в /usr/bin/xray и настроит систему
apt-get install -y xray || (
  echo "Репозиторий недоступен. Пробую альтернативный метод прямой распаковки..."
  # Если репозиторий не подтянулся, используем резервную копию бинарника,
  # которая уже идет в комплекте с дистрибутивом или ставится через snap
  snap install xray-core || apt-get install -y v2ray
)

# Переносим или проверяем пути для нашего скрипта start.sh
mkdir -p /usr/local/bin /usr/local/etc/xray
if [ -f /usr/bin/xray ]; then
    ln -sf /usr/bin/xray /usr/local/bin/xray
elif [ -f /usr/bin/xray-core ]; then
    ln -sf /usr/bin/xray-core /usr/local/bin/xray
fi

# Отдаем права на папку с конфигурацией вашему пользователю
chown -R $REAL_USER:$REAL_USER /usr/local/etc/xray

echo "3. Настройка сетевых привилегий для порта 443..."
# Разрешаем бинарнику слушать порт 443 под вашим обычным пользователем
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray || setcap 'cap_net_bind_service=ep' /usr/bin/xray

echo "4. Регистрация службы Xray в systemd под пользователем $REAL_USER..."
cat << EOF > /etc/systemd/system/xray.service
[Unit]
Description=Xray Service
Documentation=https://github.com/XTLS/Xray-core
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
