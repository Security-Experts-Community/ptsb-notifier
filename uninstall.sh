#!/bin/bash

docker stop ptsb-notifier
docker rm ptsb-notifier
docker rmi ptsb-notifier

echo "Ptsb-notifier was stopped and deleted from your system"