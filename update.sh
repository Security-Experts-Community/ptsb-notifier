#!/bin/bash

# cкрипт для автоматического обновления ptsb-notifier

set -e  # выход при любой ошибке

# цвета для вывода
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# жесткое определение директории проекта для безопасности исполнения
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$PROJECT_DIR"

echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║                   PT Sandbox Telegram Notifier Updater                    ║${NC}"
echo -e "${GREEN}║                          by @github.com/kaifuss/                          ║${NC}"
echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════════════════╝${NC}"

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
check_command "sudo"
check_command "bash"

# определяем команду docker compose
if command -v docker-compose &> /dev/null && docker-compose --version &> /dev/null; then
    COMPOSE_CMD="sudo docker-compose"
elif command -v docker &> /dev/null && docker compose version &> /dev/null; then
    COMPOSE_CMD="sudo docker compose"
else
    echo  " "
    echo -e "${RED}Error: Neither 'docker-compose' or 'docker compose' were not found on this host!${NC}"
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

# получаем последние изменения из удаленного репозитория
git fetch origin

# находим общего предка между local HEAD и origin/main репой
MERGE_BASE=$(git merge-base HEAD origin/main)

# проверяем, есть ли новые коммиты в origin/main
if [ "$(git rev-list $MERGE_BASE..origin/main --count)" -gt 0 ]; then
    echo " "
    echo -e "${GREEN}Found new verion on remote repo!${NC}"
    echo "List of new commits on original repo:"
    git log --oneline $MERGE_BASE..origin/main
else
    echo  " "
    echo -e "${GREEN}Congrats! You've already got the latest version available!${NC}"
    echo -e "${GREEN}No need for an update. Tnanks for using this app <3${NC}"
    exit 0
fi

# проверка наличия локальных изменений
echo " "
echo -e "${YELLOW}Starting update pre-checks for locally modified files...${NC}"
HAS_LOCAL_CHANGES=false
LOCAL_CHANGES_MESSAGE=""

# чтобы не отслеживать изменения в исполняемости файлов chmod
git config core.fileMode false

# 1. проверяем изменения в отслеживаемых файлах (модифицированные но не staged)
if ! git diff --quiet --ignore-all-space . ':!config/*.env' >/dev/null; then
    HAS_LOCAL_CHANGES=true
    LOCAL_CHANGES_MESSAGE+="Localy modified and not staged files:\n"
    LOCAL_CHANGES_MESSAGE+="$(git diff --name-only --ignore-all-space . ':!config/*.env')\n\n"
fi

# 2. проверяем staged изменения (добавленные в индекс)
if ! git diff --quiet --cached >/dev/null; then
    HAS_LOCAL_CHANGES=true
    LOCAL_CHANGES_MESSAGE+="Localy modified and staged changes (git add):\n"
    LOCAL_CHANGES_MESSAGE+="$(git diff --cached --name-only)\n\n"
fi

# 3. проверяем новые неотслеживаемые файлы
UNTRACKED_FILES=$(git ls-files --others --exclude-standard)
if [ -n "$UNTRACKED_FILES >/dev/null" ]; then
    HAS_LOCAL_CHANGES=true
    LOCAL_CHANGES_MESSAGE+="Localy created new files:\n"
    LOCAL_CHANGES_MESSAGE+="$UNTRACKED_FILES\n\n"
fi

# если есть локально измененые файлы, слияние которых можно навредить проекту то предупреждаем
if [ "$HAS_LOCAL_CHANGES" = true ]; then
    echo " "
    echo -e "${YELLOW}Local changes have been detected in this repository:${NC}"
    echo -e "$LOCAL_CHANGES_MESSAGE"
    echo -e "${YELLOW}Can not proceed with automatic update due to local changes.${NC}"
    echo "Please choose one of the following options:"
    echo "1. Discard all local changes and update to the latest version"
    echo "2. Keep local changes and abort automatic update"
    echo "3. Open shell to manualy resolve conflicts"
    echo " "
    read -p "Enter your choise (1-3): " -r choise
    case $choise in 
        # отменяем все изменения
        1)
            echo " "
            # сохраняем всю локальную конфигурацию перед тем, как сделаем жесткий ресет
            echo -e "${YELLOW}Back-uping config from 'config/default.env'...${NC}"
            cp -f "./config/default.env" "/tmp/default.env.bak"
            # стираем все изменения
            echo -e "${YELLOW}Discarding all local changes without saving...${NC}"
            git reset --hard origin/main >/dev/null
            git clean -fd >/dev/null
            # восстанавлием конфигурацию
            echo -e "${YELLOW}Restoring app configuration to 'config/default.env'...${NC}"
            cp -f "/tmp/default.env.bak" "./config/default.env"
            rm -f "/tmp/default.env.bak"
            echo -e "${GREEN}All local changes have been discarted. Continuing update...${NC}"
            ;;
        2)
            echo " "
            echo -e "${GREEN}Keeping local changes. Update aborted by user.${NC}"
            exit 0
            ;;
        3)
            echo " "
            echo -e "${YELLOW}Opening shell for manual resolution conficts..."
            echo -e "Hint: You can use the following commands:"
            echo -e "  git status               # View current status"
            echo -e "  git diff                 # View changes in tracked files"
            echo -e "  git diff --cached        # View staged changes"
            echo -e "  git add <file>           # Stage files"
            echo -e "  git reset <file>         # Unstage files"
            echo -e "  git checkout -- <file>   # Discard changes in file"
            echo -e "  git clean -fd            # Remove untracked files"
            echo -e " "
            echo -e "When done, type 'exit' to exit shell to continue update."
            echo -e "Hint: be careful with 'config/default.env' file${NC}"
            bash
            
            # после выхода из shell bash проверяем, остались ли конфликты
            if ! git diff --quiet --ignore-all-space . ':!config/*.env' >/dev/null || \
                ! git diff --quiet --cached >/dev/null || \
                [ -n "$(git ls-files --others --exclude-standard) >/dev/null" ]; then
                echo " "
                echo -e "${RED}Local changes still exist. Current repo state is not up-to-date with origin/main. Resolve conflicts manually.${NC}"
                echo -e "${RED}Aborting update.${NC}"
                exit 1
            fi
            # если пользователь разрешил все конфликты
            echo " "
            echo -e "${GREEN}No conflicting local changes found.${NC}" 
            # сохраняем всю локальную конфигурацию перед тем, как скачаем обновление
            echo -e "${YELLOW}Back-uping config from 'config/default.env'...${NC}"
            cp -f "./config/default.env" "/tmp/default.env.bak"
            echo -e "${YELLOW}Downloading update...${NC}"
            # скачиваем обновление
            git pull origin main >/dev/null
            git checkout main>/dev/null
            # восстанвливаем конфигурацию
            echo -e "${YELLOW}Restoring app configuration to 'config/default.env'...${NC}"
            cp -f "/tmp/default.env.bak" "./config/default.env"
            rm -f "/tmp/default.env.bak"
            ;;
        *)
            echo " "
            echo -e "${RED}Invalid unexpected input!${NC}"
            echo -e "${RED}Aborting automatic update with no changes affected.${NC}"
            exit 1
            ;;
    esac
else
    # а вот если все хорошо, то делаем 
    echo " "
    echo -e "${GREEN}No conflicting local changes found.${NC}" 
    # сохраняем всю локальную конфигурацию перед тем, как скачаем обновление
    echo -e "${YELLOW}Back-uping config from 'config/default.env'...${NC}"
    cp -f "./config/default.env" "/tmp/default.env.bak"
    echo -e "${YELLOW}Downloading update...${NC}"
    # скачиваем обновление
    git pull origin main
    # восстанвливаем конфигурацию
    echo -e "${YELLOW}Restoring app configuration to 'config/default.env'...${NC}"
    cp -f "/tmp/default.env.bak" "./config/default.env"
    rm -f "/tmp/default.env.bak"
fi

# запрашиваем подтверждение обновления контейнера
echo " "
read -p "Are you ready to proceed with restaring newer version of container? (y/N): " -r
echo " "
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo  " "
    echo -e "${GREEN}An update was canceled by user. Exiting.${NC}"
    exit 0
fi

# останавливаем текущий контейнер
echo -e "${YELLOW}Starting process of container update...${NC}"
echo -e "${YELLOW}Stopping running container of an app...${NC}"
echo " "
echo "Now you may be promted to enter sudo password to exec docker commands."
echo " "

$COMPOSE_CMD -f ./builder/docker-compose.yaml down

# восстанавливаем разрешения файлам
chmod +x install.sh
chmod +x update.sh
chmod +x uninstall.sh

# пересобираем и запускаем контейнер
echo " "
echo -e "${YELLOW}Starting container with new version of an app...${NC}"
$COMPOSE_CMD -f ./builder/docker-compose.yaml build --no-cache
$COMPOSE_CMD -f ./builder/docker-compose.yaml up -d

# проверяем статус контейнера
echo " "
echo -e "${YELLOW}Cheking if container runs normally...${NC}"
echo " "
sleep 5
if sudo docker ps | grep -q "ptsb-notifier"; then
    echo -e "${GREEN}Container running normally!${NC}"
    echo -e "${GREEN}Update of an app has been finished!${NC}"
else
    echo -e "${RED}Warning: Container is not running. Check the logs and send info to developer${NC}"
    echo -e "${YELLOW}Hint: use command 'sudo docker logs ptsb-notifier'${NC}"
fi

# показываем изменения
echo " "
echo -e "\n${GREEN}Current version of an app:${NC}"
git log --oneline HEAD^..HEAD

# возвращаем отслеживание исполняемости файлов chmod
git config core.fileMode true
