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

# Используем официальную утилиту ядра для генерации валидной пары Curve25519 ключей
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "Генерирую официальную пару ключей Reality..."
    
    KEYS_OUTPUT=$(/usr/local/bin/xray x25519)
    
    # Новый универсальный парсер: очищает строку от слов PrivateKey/PublicKey и пробелов
    PRIVATE_KEY=$(echo "$KEYS_OUTPUT" | grep -i "Private" | sed -e 's/PrivateKey://g' -e 's/Private key://g' | tr -d '[:space:]:')
    PUBLIC_KEY=$(echo "$KEYS_OUTPUT" | grep -i "Public" | sed -e 's/PublicKey://g' -e 's/Public key://g' | tr -d '[:space:]:')
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        echo "Критическая ошибка: Не удалось распарсить ключи!"
        echo "Вывод команды был: $KEYS_OUTPUT"
        exit 1
    fi
    
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

# Генерация UUID для 5 пользователей официальной командой xray uuid
for i in {1..5}; do
    var_name="CLIENT_UUID_$i"
    if [ -z "${!var_name}" ]; then
        NEW_UUID=$(/usr/local/bin/xray uuid)
        export "CLIENT_UUID_$i"="$NEW_UUID"
        echo "CLIENT_UUID_$i=${NEW_UUID}" >> .env
    else
        export "CLIENT_UUID_$i"="${!var_name}"
    fi
done

export PRIVATE_KEY PUBLIC_KEY SHORT_ID DEST_DOMAIN GRPC_SERVICE_NAME

echo "2. Сборка конфигурации и применение маски прав 0640..."
envsubst < config.template.json > /usr/local/etc/xray/config.json

# Выставляем права строго по официальной таблице XTLS: root:xray
chown root:xray /usr/local/etc/xray/config.json
chmod 0640 /usr/local/etc/xray/config.json

echo "3. Перезапуск официальной службы xray..."
systemctl restart xray

echo "--------------------------------------------------------"
echo " СЕРВЕР НА XRAY-CORE УСПЕШНО ЗАПУЩЕН!"
echo "--------------------------------------------------------"

# 4. Вывод готовых клиентских ссылок VLESS + gRPC + Reality
for i in {1..5}; do
    uuid_var="CLIENT_UUID_$i"
    CLIENT_URL="vless://${!uuid_var}@${SERVER_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=grpc&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&serviceName=${GRPC_SERVICE_NAME}#User-$i"
    
    echo -e "\n=== Ссылка для Пользователя $i ==="
    echo -e "\e[32m${CLIENT_URL}\e[0m"
    echo "--------------------------------------------------------"
done
