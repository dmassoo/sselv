#!/bin/bash
set -e

cd "$(dirname "$0")"

# 1. Проверка .env и жесткая очистка от пустых строк, пробелов и Windows-переносов
if [ -f .env ]; then
    # Читаем файл построчно
    while IFS= read -r line || [ -n "$line" ]; do
        # 1. Удаляем скрытые символы переноса строк Windows (\r)
        # 2. Удаляем лишние пробелы в начале и конце строки
        clean_line=$(echo "$line" | tr -d '\r' | xargs)
        
        # Фильтр: если строка пустая ИЛИ начинается с символа # (комментарий) — пропускаем её
        if [[ -z "$clean_line" || "$clean_line" =~ ^# ]]; then
            continue
        fi
        
        # Если в строке нет знака равенства (кривой формат) — тоже пропускаем
        if [[ ! "$clean_line" == *"="* ]]; then
            continue
        fi

        # Экспортируем только валидные переменные (например, SERVER_IP=194.x.x.x)
        export "$clean_line"
    done < .env
else
    echo "Ошибка: Файл .env не найден! Создайте его рядом со скриптом."
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

echo "2. Сборка конфигурации..."
# Принудительно экспортируем переменные, чтобы envsubst их точно увидел
export SERVER_IP DEST_DOMAIN PRIVATE_KEY PUBLIC_KEY SHORT_ID GRPC_SERVICE_NAME
export CLIENT_UUID_1 CLIENT_UUID_2 CLIENT_UUID_3 CLIENT_UUID_4 CLIENT_UUID_5

# Собираем конфиг одной командой
envsubst < config.template.json > /usr/local/etc/xray/config.json

# Выставляем права по официальной спецификации безопасности XTLS
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
