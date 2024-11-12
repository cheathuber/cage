#!/bin/bash

# read APP_NAME from .env file
set -a
. ./.env
set +a

docker compose build || exit 1
docker compose up -d 

sleep 10

STATUS=$(docker inspect --format='{{.State.Health.Status}}' ${APP_NAME})

echo $STATUS
