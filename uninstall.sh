#!/bin/bash

# проверяем, запущен ли контейнер
if docker ps -q --filter "name=ptsb-notifier" | grep -q .; then
    echo "Останавливаем контейнер ptsb-notifier..."
    docker stop ptsb-notifier
else
    echo "Контейнер ptsb-notifier не запущен."
fi

echo " "

# проверяем, существует ли контейнер
if docker ps -a -q --filter "name=ptsb-notifier" | grep -q .; then
    echo "Удаляем контейнер ptsb-notifier..."
    docker rm ptsb-notifier
else
    echo "Контейнер ptsb-notifier не найден."
fi

echo " "

# проверяем, существует ли образ
if docker images --filter "reference=builder-ptsb-notifier" -q | grep -q .; then
    echo "Удаляем образ builder-ptsb-notifier..."
    docker rmi builder-ptsb-notifier
else
    echo "Образ builder-ptsb-notifier не найден."
fi

echo " "

echo "Ptsb-notifier был успешно удалён из системы."
