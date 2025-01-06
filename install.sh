#!/bin/bash

# отсюда берем значения
if [ -f ./config/default.env ]; then
    source ./config/default.env
fi

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                                  WELCOME                                  ║"
echo "║                       PT Sandbox Telegram Notifier                        ║"
echo "║                          by @github.com/kaifuss/                          ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"

echo " "
echo "Перед запуском приложения его необходимо предварительно настроить."
echo "Описание параметров приложения приведено ниже:"
echo "═════════════════════════════════════════════════════════════════════════════"
echo "PTSB_MAIN_WEB: Адрес веб-интерфейса PT Sandbox, указываемый в браузере."
echo "THREAT_FILTER_MODE: Уровень опасности вердикта, согласно которому определяется - подходит ли текущее событие для отправки или нет."
echo "TG_BOT_TOKEN: Токен доступа к Вашему Telegram-боту, полученный от BotFather."
echo "TG_CHAT_ID: ID чата в Telegram, куда необходимо отправлять уведомления."
echo "UTC_CUSTOM_OFFSET: Смещение Вашего часового пояса относительно UTC (+0) в часах. Например, смещение для МСК = 3. Для Калининграда = -1"
echo "═════════════════════════════════════════════════════════════════════════════"
echo " "

input_with_default() {
  local var_name=$1
  local default_value=$2
  local input
  local escaped_default_value

  escaped_default_value=$(printf '%q' "$default_value")

  read -p "Введите значение для ${var_name} (текущее: ${escaped_default_value}): " input
  if [[ $input =~ [^a-zA-Z0-9_] ]]; then
    export $var_name="'${input:-$default_value}'"
  else
    export $var_name=${input:-$default_value}
  fi
}

input_with_default "PTSB_MAIN_WEB" "$PTSB_MAIN_WEB"
input_with_default "THREAT_FILTER_MODE" "$THREAT_FILTER_MODE"
input_with_default "TG_BOT_TOKEN" "$TG_BOT_TOKEN"
input_with_default "TG_CHAT_ID" "$TG_CHAT_ID"
input_with_default "UTC_CUSTOM_OFFSET" "$UTC_CUSTOM_OFFSET"

cat << EOF > ./config/default.env
PTSB_MAIN_WEB=${PTSB_MAIN_WEB}
THREAT_FILTER_MODE=${THREAT_FILTER_MODE}
TG_BOT_TOKEN=${TG_BOT_TOKEN}
TG_CHAT_ID=${TG_CHAT_ID}
UTC_CUSTOM_OFFSET=${UTC_CUSTOM_OFFSET}
EOF

echo " "
echo "═════════════════════════════════════════════════════════════════════════════"
echo " "

if command -v docker-compose &> /dev/null && docker-compose --version &> /dev/null; then
    compose_cmd="docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    compose_cmd="docker compose"
else
    echo "Ошибка: Команды 'docker-compose' или 'docker compose' не были найдены. Пожалуйста, установите docker & docker-compose."
    exit 1
fi

builder_dir="./builder"

if docker images | grep -q "ptsb-notifier"; then
    read -p "Образ 'ptsb-notifier' уже существует. Вы хотите обновить образ или пересобрать его заново? (update/rebuild): " choice
    case $choice in
        update)
            $compose_cmd -f "$builder_dir/docker-compose.yaml" down
            $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
            ;;
        rebuild)
            $compose_cmd -f "$builder_dir/docker-compose.yaml" down
            docker rmi ptsb-notifier
            $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
            ;;
        *)
            echo "Некорректный ввод. Пожалуйста, введите 'update' или 'rebuild'."
            ;;
    esac
else
    $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
fi