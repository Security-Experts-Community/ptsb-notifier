#!/bin/bash

# скрипт удаления приложения

# проверяем, запущен ли контейнер
if docker ps -q --filter "name=ptsb-notifier" | grep -q .; then
    echo "Stopping container of ptsb-notifier..."
    docker stop ptsb-notifier
else
    echo "Container ptsb-notifier already stopped. Going on..."
fi

echo " "

# проверяем, существует ли контейнер
if docker ps -a -q --filter "name=ptsb-notifier" | grep -q .; then
    echo "Removing container ptsb-notifier..."
    docker rm ptsb-notifier
else
    echo "Container ptsb-notifier was not found. Going on..."
fi

echo " "

# проверяем, существует ли образ
if docker images --filter "reference=builder-ptsb-notifier" -q | grep -q .; then
    echo "Removing image of builder-ptsb-notifier..."
    docker rmi builder-ptsb-notifier
else
    echo "Image builder-ptsb-notifier was not found."
fi

echo " "

echo "Ptsb-notifier was successfully removed from this host."
