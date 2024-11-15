#!/bin/bash

# Read APP_NAME, APP_ENV from .env file
set -a
. ./.env
set +a

COMPOSE_FILES=""
COPY_ASSETS=""

# Add environment-specific compose file if APP_ENV is staging or production
if [[ "$APP_ENV" == "staging" || "$APP_ENV" == "production" ]]; then
    COMPOSE_FILES="$COMPOSE_FILES -f compose.yml"
    COMPOSE_FILES="$COMPOSE_FILES -f compose.$APP_ENV.yml"
fi

if ! docker compose $COMPOSE_FILES build; then
    bash notify.sh "Build failed" "The Docker image build for ${APP_NAME} failed. Check the build logs for details."
    exit 1
fi

docker compose $COMPOSE_FILES up -d 

# Copy Assets from Build Stage 1 to host:
container_id=$(docker ps -qf "name=^${APP_NAME}$")
if [[ -n "$container_id" && -n "$COPY_ASSETS" ]]; then
    echo "Copying assets from container ${container_id} to host..."
    #docker cp ${container_id}:/var/www/html/public/ ./public
    # use tar -h instead of cp to dereference symlinks:
    docker exec  ${container_id} tar -C /var/www/html/public -hcf - . --totals| tar -C ./public -xf -
    echo "Assets copied successfully."
else
    echo "Container for ${APP_NAME} not found or COPY_ASSETS not set. Skipping asset copy."
fi

# Function to check container status
check_container_status() {
    local max_attempts=12  # Maximum number of attempts (2 minutes total)
    local attempt=1
    local wait_time=10  # Wait time in seconds between attempts

    while [ $attempt -le $max_attempts ]; do
        # Check if container has a health check
        if docker inspect --format='{{if .State.Health}}true{{else}}false{{end}}' ${APP_NAME} | grep -q true; then
            HEALTH_CHECK=$(docker inspect --format='{{.State.Health.Status}}' ${APP_NAME})
            echo "Container has health check. Status: $HEALTH_CHECK"
            case $HEALTH_CHECK in
                healthy)
                    return 0  # Healthy
                    ;;
                starting)
                    echo "Attempt $attempt: Container ${APP_NAME} is still starting. Waiting..."
                    sleep $wait_time
                    attempt=$((attempt + 1))
                    ;;
                *)
                    return 2  # Unhealthy
                    ;;
            esac
        else
            STATUS=$(docker inspect --format='{{.State.Status}}' ${APP_NAME})
            echo "Container has no health check. Status: $STATUS"
            case $STATUS in
                running)
                    return 1  # Running (no health check)
                    ;;
                created|starting)
                    echo "Attempt $attempt: Container ${APP_NAME} is still initializing. Waiting..."
                    sleep $wait_time
                    attempt=$((attempt + 1))
                    ;;
                *)
                    return 3  # Not running
                    ;;
            esac
        fi
    done

    return 4  # Timeout
}

# Check container status
check_container_status
status_code=$?

SUB_COMMIT=$(git submodule foreach --quiet 'git log -1 --pretty=format:"%h - %s (%cr)"')

case $status_code in
    0)
        bash notify.sh "Deployment successful" "The ${APP_NAME} container is healthy. Latest commit: $SUB_COMMIT"
        ;;
    1)
        bash notify.sh "Deployment successful" "The ${APP_NAME} container is running (no health check). Latest commit: $SUB_COMMIT"
        ;;
    2)
        FINAL_STATUS=$(docker inspect --format='{{.State.Health.Status}}' ${APP_NAME})
        bash notify.sh "Deployment issue" "The ${APP_NAME} container health check failed: ${FINAL_STATUS}. Latest commit: $SUB_COMMIT"
        ;;
    3)
        FINAL_STATUS=$(docker inspect --format='{{.State.Status}}' ${APP_NAME})
        bash notify.sh "Deployment issue" "The ${APP_NAME} container is not running. Status: ${FINAL_STATUS}. Latest commit: $SUB_COMMIT"
        ;;
    4)
        bash notify.sh "Deployment issue" "The ${APP_NAME} container did not become ready within the allocated time. Latest commit: $SUB_COMMIT"
        ;;
    *)
        bash notify.sh "Deployment issue" "An unexpected error occurred while checking ${APP_NAME} container status. Latest commit: $SUB_COMMIT"
        ;;
esac
