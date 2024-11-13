#!/bin/bash

# Read APP_NAME from .env file
set -a
. ./.env
set +a

docker compose build || exit 1
docker compose up -d 

check_container_health() {
    local max_attempts=12  # Maximum number of attempts (1 min total)
    local attempt=1
    local wait_time=5  # Wait time in seconds between attempts

    while [ $attempt -le $max_attempts ]; do
        HEALTH_CHECK=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' ${APP_NAME})
        
        if [ "$HEALTH_CHECK" = "healthy" ] || [ "$HEALTH_CHECK" = "running" ]; then
            echo "Container ${APP_NAME} is ready. Status: $HEALTH_CHECK"
            return 0
        elif [ "$HEALTH_CHECK" = "starting" ]; then
            echo "Attempt $attempt: Container ${APP_NAME} is still starting. Waiting..."
            sleep $wait_time
            attempt=$((attempt + 1))
        else
            echo "Container ${APP_NAME} is in an unexpected state: $HEALTH_CHECK"
            return 1
        fi
    done

    echo "Container ${APP_NAME} did not become ready within the allocated time."
    return 1
}

if check_container_health; then
    echo send_google_chat_update.sh "Deployment successful" "The ${APP_NAME} container is ready and healthy."
else
    FINAL_STATUS=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}{{.State.Status}}{{end}}' ${APP_NAME})
    echo send_google_chat_update.sh "Deployment issue" "The ${APP_NAME} container health is ${FINAL_STATUS} after multiple checks."
fi

