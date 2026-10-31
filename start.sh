#!/bin/bash
set -e

cd "$(dirname "$0")"

# 1. Проверка .env
if [ -f .env ]; then
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Ошибка: Файл .env не найден!"
    exit 1
fi

if [ -z "$SERVER_IP" ] || [ -z "$DEST_DOMAIN" ]; then
    echo "Ошибка: В .env обязаны быть заполнены переменные SERVER_IP и DEST_DOMAIN."
    exit 1
fi

echo "1. Проверка и генерация криптографических параметров..."

# Если ключей Reality нет в .env, генерируем их чистыми средствами openssl/bash
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "Генерирую пару ключей Reality..."
    # Так как xray x25519 недоступен, генерируем стандартную надежную пару ключей x25519 через openssl
    openssl genpkey -algorithm x25519 -out /tmp/private.key
    PRIVATE_KEY=$(openssl pkey -in /tmp/private.key -text -noout | grep -v "x25519" | tr -d '[:space:]:' | head -n 1 | cut -c1-44)
    # Используем фиксированный публичный ключ или генерируем из приватного
    PUBLIC_KEY=$(openssl pkey -in /tmp/private.key -pubout -outform DER | tail -c 32 | base64)
    rm -f /tmp/private.key
    
    echo "PRIVATE_KEY=${PRIVATE_KEY}" >> .env
    echo "PUBLIC_KEY=${PUBLIC_KEY}" >> .env
fi

if [ -z "$SHORT_ID" ]; then
    SHORT_ID=$(openssl rand -hex 4)
    echo "SHORT_ID=${SHORT_ID}" >> .env
fi

if [ -z "$GRPC_SERVICE_NAME" ]; then
    GRPC_SERVICE_NAME="api-stream-$(openssl rand -hex 3)"
    echo "GRPC_SERVICE_NAME=${GRPC_SERVICE_NAME}" >> .env
fi

# 2. Генерация UUID системными средствами Linux
for i in {1..5}; do
    var_name="CLIENT_UUID_$i"
    if [ -z "${!var_name}" ]; then
        NEW_UUID=$(cat /proc/sys/kernel/random/uuid)
        export "CLIENT_UUID_$i"="$NEW_UUID"
        echo "CLIENT_UUID_$i=${NEW_UUID}" >> .env
    else
        export "CLIENT_UUID_$i"="${!var_name}"
    fi
done

export PRIVATE_KEY PUBLIC_KEY SHORT_ID DEST_DOMAIN GRPC_SERVICE_NAME

echo "2. Сборка конфигурации..."
mkdir -p /usr/local/etc/xray
envsubst < config.template.json > /usr/local/etc/xray/config.json

echo "3. Перезапуск службы через systemd..."
systemctl restart xray

echo "--------------------------------------------------------"
echo " СЕРВЕР ЗАПУЩЕН!"
echo "--------------------------------------------------------"

# 3. Вывод готовых клиентских ссылок (без тяжелого qrencode, который может вешать консоль)
for i in {1..5}; do
    uuid_var="CLIENT_UUID_$i"
    CLIENT_URL="vless://${!uuid_var}@${SERVER_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=grpc&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&serviceName=${GRPC_SERVICE_NAME}#User-$i"
    
    echo -e "\n=== Ссылка для Пользователя $i ==="
    echo -e "\e[32m${CLIENT_URL}\e[0m"
    echo "--------------------------------------------------------"
done
