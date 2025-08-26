#!/bin/bash

# cкрипт для автоматического обновления ptsb-notifier

set -e  # выход при любой ошибке

# цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   PT Sandbox Telegram Notifier Updater                    ║${NC}"
echo -e "${GREEN}║                          by @github.com/kaifuss/                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"

# жесткое определение директории проекта для безопасности исполнения
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

# проверка наличия команд на всякий случай, если что-то было удалено
# позволит не убить контеннер без возможности обновления
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo  " "
        echo -e "${RED}Error: Command '$1' was not found on this host!${NC}"
        echo -e "${RED}Aborting update.${NC}"
        exit 1
    fi
}
# проверка наличия команд
check_command "git"
check_command "docker"

# определяем команду docker compose
if command -v docker-compose &> /dev/null && docker-compose --version &> /dev/null; then
    COMPOSE_CMD="sudo docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_CMD="sudo docker compose"
else
    echo  " "
    echo -e "${RED}Error: Neither 'docker-compose' or 'docker compose' was not found on this host!${NC}"
    echo -e "${RED}Aborting update.${NC}"
    exit 1
fi

# проверяем, является ли текущая директория git репой
# позволяет трекать версии на наличие обнов
if [ ! -d ".git" ]; then
    echo  " "
    echo -e "${RED}Error: Current directory is not a git repo! You can not update application via update.sh script.${NC}"
    echo -e "${RED}Aborting update.${NC}"
    echo  " "
    echo -e "${YELLOW}Hint: you can do clear installation of an app instead.${NC}"
    exit 1
fi

# начинаем процесс сравнения информации о текущей и удаленной версиях
echo  " "
echo -e "${YELLOW}Checking for available updates of an app...${NC}"

# сохраняем текущий коммит
CURRENT_COMMIT=$(git rev-parse HEAD)

# получаем последние изменения из удаленного репозитория
git fetch origin

# проверяем, есть ли новые коммиты
REMOTE_COMMIT=$(git rev-parse origin/main)
if [ "$CURRENT_COMMIT" = "$REMOTE_COMMIT" ]; then
    echo  " "
    echo -e "${GREEN}Congrats! You've already got the latest version available!${NC}"
    echo "No need for an update."
    exit 0
fi

echo  " "
echo -e "${YELLOW}A newer version of app was found!${NC}"
echo -e "Current version commit id: ${CURRENT_COMMIT:0:7}"
echo -e "New version commit id:   ${REMOTE_COMMIT:0:7}"

# запрашиваем подтверждение обновления
echo  " "
read -p "Do you want to proceed with update? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo  " "
    echo -e "${YELLOW}An update was canceled by user. Exiting.${NC}"
    exit 0
fi

# останавливаем текущий контейнер
echo  " "
echo "═════════════════════════════════════════════════════════════════════════════"
echo -e "${GREEN}Starting process of an update...${NC}"
echo "═════════════════════════════════════════════════════════════════════════════"
echo -e "${YELLOW}Stopping running container of an app...${NC}"
$COMPOSE_CMD -f ./builder/docker-compose.yaml down

# сохраняем конфигурацию на будущее
echo -e "${YELLOW}Copying app configuration...${NC}"
if [ -f "./config/default.env" ]; then
    cp -f "./config/default.env" "/tmp/ptsb-notifier.env.bak"
    echo -e "${GREEN}Config file was copied into /tmp/ptsb-notifier.env.bak${NC}"
else
    echo -e "${YELLOW}Warning: Config file in ./config/default.env was not found${NC}"
fi

# скачивание новой версии приложения с git kaifuss
echo " "
echo -e "${YELLOW}Downloading new update of an app from git repo...${NC}"
git fetch origin
git reset --hard origin/main

# восстанавливаем конфигурацию
if [ -f "/tmp/ptsb-notifier.env.bak" ]; then
    echo -e " "
    echo -e "${YELLOW}Restoring configuration from copied file...${NC}"
    cp -f "/tmp/ptsb-notifier.env.bak" "./config/default.env"
    rm -f "/tmp/ptsb-notifier.env.bak"
    echo -e "${GREEN}App configuration was restored${NC}"
fi

# восстанавливаем разрешения файлам
chmod +x install.sh
chmox +x update.sh
chmod +x uninstall.sh

# пересобираем и запускаем контейнер
echo "═════════════════════════════════════════════════════════════════════════════"
echo -e "${Green}Starting container with new version of an app...${NC}"
echo "═════════════════════════════════════════════════════════════════════════════"
$COMPOSE_CMD -f ./builder/docker-compose.yaml build --no-cache
$COMPOSE_CMD -f ./builder/docker-compose.yaml up -d

# проверяем статус контейнера
sleep 5
if docker ps | grep -q "ptsb-notifier"; then
    echo -e "${GREEN}Container running normally!${NC}"
    echo -e "${GREEN}Update of an app has been finished!${NC}"
else
    echo -e "${RED}Warning: Container is not running. Check the logs and send info to developer${NC}"
    echo "docker logs ptsb-notifier"
fi

# показываем изменения
echo -e "\n${YELLOW}Latest changes of PTSB Notifier:${NC}"
git log --oneline HEAD^..HEAD