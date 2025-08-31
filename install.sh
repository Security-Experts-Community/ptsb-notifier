#!/bin/bash

# скрипт установки приложения

# отсюда берем значения
if [ -f ./config/default.env ]; then
    source ./config/default.env
fi

# жесткое определение директории проекта для безопасности исполнения
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo "╔═══════════════════════════════════════════════════════════════════════════╗"
echo "║                                  WELCOME                                  ║"
echo "║                       PT Sandbox Telegram Notifier                        ║"
echo "║                          by @github.com/kaifuss/                          ║"
echo "╚═══════════════════════════════════════════════════════════════════════════╝"

# проверка новых обновлений
# получаем последние изменения из удаленного репозитория
git fetch origin

# находим общего предка между local HEAD и origin/main репой
MERGE_BASE=$(git merge-base HEAD origin/main)

# проверяем, есть ли новые коммиты в origin/main
if [ "$(git rev-list $MERGE_BASE..origin/main --count)" -gt 0 ]; then
    echo " "
    echo "Hint: Original repo has new available updates for an app."
    echo "Hint: Now you will work with your current app version."
    echo "Hint: If you want to install the newest version - run './update.sh' script."
fi

echo " "
echo "Before running an application you must set up it."
echo "Here is the description of its parameters:"
echo "═════════════════════════════════════════════════════════════════════════════"
echo "PTSB_MAIN_WEB: Web address of PT Sandbox (without https://), (FQDN or IP)."
echo "THREAT_FILTER_MODE: The danger level of the verdict, according to which it is determined whether the current event is suitable for sending or not."
echo "TG_BOT_TOKEN: Access token to your Telegram-bot, that you got from BotFather."
echo "TG_CHAT_ID: The ID of the Telegram chat to send notifications to."
echo "UTC_CUSTOM_OFFSET: The offset of your time zone relative to UTC (+0) in hours. For example, the offset for MSK = 3. For Kaliningrad = -1"
echo "═════════════════════════════════════════════════════════════════════════════"
echo " "

input_with_default() {
  local var_name=$1
  local default_value=$2
  local input
  local escaped_default_value

  escaped_default_value=$(printf '%q' "$default_value")

  read -p "Enter value for parameter ${var_name} (current: ${escaped_default_value}): " input
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
    echo "Error: commands 'docker-compose' either 'docker compose' were not found. Please, install 'docker' & 'docker-compose' first."
    exit 1
fi

builder_dir="./builder"

if docker images | grep -q "ptsb-notifier"; then
    read -p "Image of 'ptsb-notifier' already exists. Do you want to update parameters of application or fully rebuild? (update/rebuild): " choice
    case $choice in
        update)
            $compose_cmd -f "$builder_dir/docker-compose.yaml" down
            $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
            ;;
        rebuild)
            $compose_cmd -f "$builder_dir/docker-compose.yaml" down
            docker images --filter "reference=builder-ptsb-notifier" -q | xargs -r docker rmi
            $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
            ;;
        *)
            echo "Incorrect input. Please, input 'update' or 'rebuild'."
            ;;
    esac
else
    $compose_cmd -f "$builder_dir/docker-compose.yaml" up -d
fi
