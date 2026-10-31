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

echo "3. Скачивание ядра Xray-core через стабильный хаб-зеркало..."
rm -f /tmp/xray.zip
# Используем зеркало репозитория XTLS, которое не отдает HTML-заглушки
curl -f -L -o /tmp/xray.zip "https://moeyy.xyz"

echo "4. Распаковка бинарника и настройка FHS директорий по стандарту XTLS..."
mkdir -p /usr/local/bin /usr/local/etc/xray /usr/local/share/xray /var/log/xray

unzip -o /tmp/xray.zip -d /tmp/xray_unpack
mv -f /tmp/xray_unpack/xray /usr/local/bin/xray
mv -f /tmp/xray_unpack/geoip.dat /usr/local/share/xray/geoip.dat
mv -f /tmp/xray_unpack/geosite.dat /usr/local/share/xray/geosite.dat
rm -rf /tmp/xray.zip /tmp/xray_unpack

# Выставляем жесткие права из официальной спецификации XTLS
chmod 0755 /usr/local/bin/xray
chown root:root /usr/local/bin/xray

chown root:xray /usr/local/etc/xray
chmod 0750 /usr/local/etc/xray

chown -R xray:xray /usr/local/share/xray
chmod 0755 /usr/local/share/xray
chmod 0644 /usr/local/share/xray/*.dat

chown xray:xray /var/log/xray
chmod 0700 /var/log/xray

# Разрешаем вашему SSH-пользователю управлять конфигурацией через start.sh
usermod -aG xray $REAL_USER

echo "5. Настройка сетевых привилегий Linux для порта 443..."
setcap 'cap_net_bind_service=ep' /usr/local/bin/xray

echo "6. Создание официальной службы xray.service..."
cat << 'EOF' > /etc/systemd/system/xray.service
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

# Перезагружаем менеджер служб и активируем автозапуск
systemctl daemon-reload
systemctl enable xray

# Удаляем старый v2ray, чтобы он не занимал порты
systemctl stop v2ray &>/dev/null || true
systemctl disable v2ray &>/dev/null || true
apt-get remove -y v2ray &>/dev/null || true

echo "--------------------------------------------------------"
echo " Установка Xray-core по стандарту XTLS успешно завершена!"
echo " Запустите финальную настройку: sudo ./start.sh"
echo "--------------------------------------------------------"
