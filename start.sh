#!/bin/bash
set -e

# Переходим в директорию скрипта, чтобы пути были относительными
cd "$(dirname "$0")"

# 1. Проверка наличия файла .env
if [ -f .env ]; then
    # Экспортируем существующие переменные
    export $(cat .env | grep -v '^#' | xargs)
else
    echo "Ошибка: Файл .env не найден! Создайте его рядом со скриптом."
    exit 1
fi

if [ -z "$SERVER_IP" ] || [ -z "$DEST_DOMAIN" ]; then
    echo "Ошибка: В .env обязаны быть заполнены переменные SERVER_IP и DEST_DOMAIN."
    exit 1
fi

echo "1. Проверка и генерация криптографических параметров Reality..."

# Если ключей Reality нет в .env, генерируем их через xray и сохраняем в .env
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    # Проверяем, установлен ли xray, чтобы не упасть при первом запуске
    if ! command -v xray &> /dev/null; then
        echo "Служба xray еще не установлена. Запустите сначала sudo ./install.sh"
        exit 1
    fi
    KEYS=$(xray x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    echo "PRIVATE_KEY=${PRIVATE_KEY}" >> .env
    echo "PUBLIC_KEY=${PUBLIC_KEY}" >> .env
fi

# Генерируем ShortID, если его нет
if [ -z "$SHORT_ID" ]; then
    SHORT_ID=$(openssl rand -hex 4)
    echo "SHORT_ID=${SHORT_ID}" >> .env
fi

# Генерируем скрытое имя gRPC-службы, если его нет
if [ -z "$GRPC_SERVICE_NAME" ]; then
    GRPC_SERVICE_NAME="api-stream-$(openssl rand -hex 3)"
    echo "GRPC_SERVICE_NAME=${GRPC_SERVICE_NAME}" >> .env
fi

# 2. Проверка и генерация постоянных UUID для 5 пользователей
for i in {1..5}; do
    var_name="CLIENT_UUID_$i"
    if [ -z "${!var_name}" ]; then
        NEW_UUID=$(xray uuid)
        export "CLIENT_UUID_$i"="$NEW_UUID"
        echo "CLIENT_UUID_$i=${NEW_UUID}" >> .env
    else
        # Перестраховка: экспортируем уже существующий UUID из .env
        export "CLIENT_UUID_$i"="${!var_name}"
    fi
done

# Принудительно экспортируем технические переменные для утилиты envsubst
export PRIVATE_KEY PUBLIC_KEY SHORT_ID DEST_DOMAIN GRPC_SERVICE_NAME

echo "2. Сборка конфигурационного файла Xray..."
mkdir -p /usr/local/etc/xray
envsubst < config.template.json > /usr/local/etc/xray/config.json

echo "3. Перезапуск службы Xray через systemd..."
systemctl restart xray

echo "--------------------------------------------------------"
echo " СЕРВЕР УСПЕШНО ЗАПУЩЕН И НАХОДИТСЯ ПОД УПРАВЛЕНИЕМ SYSTEMD"
echo "--------------------------------------------------------"

# 4. Вывод готовых клиентских ссылок VLESS + Reality + gRPC
for i in {1..5}; do
    uuid_var="CLIENT_UUID_$i"
    CLIENT_URL="vless://${!uuid_var}@${SERVER_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=grpc&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&serviceName=${GRPC_SERVICE_NAME}#User-$i"
    
    echo -e "\n=== Ссылка для Пользователя $i ==="
    echo -e "\e[32m${CLIENT_URL}\e[0m"
    echo "Генерация QR-кода для Пользователя $i..."
    qrencode -t ansiutf8 "$CLIENT_URL"
    echo "--------------------------------------------------------"
done
