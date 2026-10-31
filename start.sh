#!/bin/bash
set -e

cd "$(dirname "$0")"

# 1. Чтение и очистка .env
if [ -f .env ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        clean_line=$(echo "$line" | tr -d '\r' | xargs)
        if [[ ! -z "$clean_line" && ! "$clean_line" =~ ^# ]]; then
            export "$clean_line"
        fi
    done < .env
else
    echo "Ошибка: Файл .env не найден!"
    exit 1
fi

if [ -z "$SERVER_IP" ] || [ -z "$DEST_DOMAIN" ]; then
    echo "Ошибка: В .env обязаны быть заполнены переменные SERVER_IP and DEST_DOMAIN."
    exit 1
fi

echo "1. Проверка и генерация криптографических параметров..."
if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
    echo "Генерирую официальную пару ключей Reality..."
    /usr/local/bin/xray x25519 > /tmp/xray_keys.txt
    
    KEYS=$(python3 -c "
import os
if os.path.exists('/tmp/xray_keys.txt'):
    with open('/tmp/xray_keys.txt', 'r', encoding='utf-8') as f:
        priv, pub = '', ''
        for line in f:
            clean = line.strip()
            if 'PrivateKey:' in clean:
                priv = clean.split('PrivateKey:')[-1].strip()
            elif 'Password (PublicKey):' in clean:
                pub = clean.split('Password (PublicKey):')[-1].strip()
        print(f'{priv} {pub}')
")
    rm -f /tmp/xray_keys.txt

    PRIVATE_KEY=$(echo "$KEYS" | awk '{print $1}')
    PUBLIC_KEY=$(echo "$KEYS" | awk '{print $2}')
    
    if [ -z "$PRIVATE_KEY" ] || [ -z "$PUBLIC_KEY" ]; then
        echo "Критическая ошибка: Не удалось распарсить ключи!"
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

export SERVER_IP DEST_DOMAIN PRIVATE_KEY PUBLIC_KEY SHORT_ID GRPC_SERVICE_NAME
export CLIENT_UUID_1 CLIENT_UUID_2 CLIENT_UUID_3 CLIENT_UUID_4 CLIENT_UUID_5

echo "2. Сборка конфигурации (Прямая замена через sed)..."

# Читаем шаблон во временный файл
cp config.template.json /tmp/config.tmp.json

# Мягко и гарантированно заменяем каждую переменную на её реальное значение
sed -i "s|\${SERVER_IP}|${SERVER_IP}|g" /tmp/config.tmp.json
sed -i "s|\${DEST_DOMAIN}|${DEST_DOMAIN}|g" /tmp/config.tmp.json
sed -i "s|\${PRIVATE_KEY}|${PRIVATE_KEY}|g" /tmp/config.tmp.json
sed -i "s|\${PUBLIC_KEY}|${PUBLIC_KEY}|g" /tmp/config.tmp.json
sed -i "s|\${SHORT_ID}|${SHORT_ID}|g" /tmp/config.tmp.json
sed -i "s|\${GRPC_SERVICE_NAME}|${GRPC_SERVICE_NAME}|g" /tmp/config.tmp.json
sed -i "s|\${CLIENT_UUID_1}|${CLIENT_UUID_1}|g" /tmp/config.tmp.json
sed -i "s|\${CLIENT_UUID_2}|${CLIENT_UUID_2}|g" /tmp/config.tmp.json
sed -i "s|\${CLIENT_UUID_3}|${CLIENT_UUID_3}|g" /tmp/config.tmp.json
sed -i "s|\${CLIENT_UUID_4}|${CLIENT_UUID_4}|g" /tmp/config.tmp.json
sed -i "s|\${CLIENT_UUID_5}|${CLIENT_UUID_5}|g" /tmp/config.tmp.json

# Переносим готовый файл в системную папку
mv /tmp/config.tmp.json /usr/local/etc/xray/config.json

# Выставляем права по стандарту безопасности XTLS
chown root:xray /usr/local/etc/xray/config.json
chmod 0640 /usr/local/etc/xray/config.json

echo "3. Перезапуск официальной службы xray..."
systemctl restart xray

echo "--------------------------------------------------------"
echo " СЕРВЕР НА XRAY-CORE УСПЕШНО ЗАПУЩЕН!"
echo "--------------------------------------------------------"

for i in {1..5}; do
    uuid_var="CLIENT_UUID_$i"
    CLIENT_URL="vless://${!uuid_var}@${SERVER_IP}:443?security=reality&encryption=none&pbk=${PUBLIC_KEY}&headerType=none&fp=chrome&type=grpc&sni=${DEST_DOMAIN}&sid=${SHORT_ID}&serviceName=${GRPC_SERVICE_NAME}#User-$i"
    echo -e "\n=== Ссылка для Пользователя $i ==="
    echo -e "\e[32m${CLIENT_URL}\e[0m"
    echo "--------------------------------------------------------"
done
