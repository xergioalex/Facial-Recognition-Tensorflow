#!/bin/bash

# Utils functions
. ./../utils.sh

# Create envs vars if don't exist
ENV_FILES=(".env" "flask/.env" "nginx/site.template" "nginx/site.template.ssl" "nginx/.env" "nginx/nginx.conf" "nginx/renewssl.sh" "nginx/crontab")
utils.check_envs_files "${ENV_FILES[@]}"

# Load environment vars, to use from console, run follow command:
utils.load_environment
utils.load_environment_flask
utils.load_environment_nginx

# Menu options
if [[ "$1" == "build" ]]; then
    utils.printer "Building images"
    docker-compose -f docker-compose.build.yaml build
elif [[ "$1" == "push" ]]; then
    echo ${CONTAINER_REGISTRY_PREFIX}
    utils.printer "Tagging images flask..."
    utils.printer "${COMPOSE_PROJECT_NAME}_${SERVICE_FLASK_BUILD_NAME} --> ${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_FLASK_BUILD_NAME}-${SERVICE_FLASK_BUILD_TAG_CALC}"
    docker tag "${COMPOSE_PROJECT_NAME}_${SERVICE_FLASK_BUILD_NAME}" "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_FLASK_BUILD_NAME}-${SERVICE_FLASK_BUILD_TAG_CALC}"
    utils.printer "Tagging images nginx..."
    utils.printer "${COMPOSE_PROJECT_NAME}_${SERVICE_NGINX_BUILD_NAME} --> ${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_NGINX_BUILD_NAME}-${SERVICE_NGINX_BUILD_TAG_CALC}"
    docker tag "${COMPOSE_PROJECT_NAME}_${SERVICE_NGINX_BUILD_NAME}" "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_NGINX_BUILD_NAME}-${SERVICE_NGINX_BUILD_TAG_CALC}"
elif [[ "$1" == "deploy" ]]; then
    utils.printer "Deploying services"
    docker-compose up -d flask
elif [[ "$1" == "server.up" ]]; then
    if [[ "$2" == "secure" ]]; then
        utils.printer "Set nginx service renewssl vars..."
        utils.nginx_renewssl_vars
        utils.printer "Stopping nginx machine if it's running..."
        docker-compose stop nginx
        utils.printer "Creating letsencrypt certifications files..."
        docker-compose up certbot
        utils.printer "Setting up cron job for auto renew ssl..."
        CRONPATH=/opt/crons/${COMPOSE_PROJECT_NAME}
        mkdir -p $CRONPATH
        cp nginx/renewssl.sh $CRONPATH/renewssl.sh
        chmod +x $CRONPATH/renewssl.sh
        touch $CRONPATH/renewssl.logs
        cp nginx/crontab $CRONPATH/crontab
        crontab $CRONPATH/crontab
    fi
    utils.printer "Starting nginx machine..."
    docker-compose up -d nginx
    docker-compose restart nginx
elif [[ "$1" == "up" ]]; then
    # Build meteor && docker images
    bash docker.sh build $2
    # Pushing images to docker hub
    bash docker.sh push
    # Deploying services to local host
    bash docker.sh deploy
    # Set server configuration
    bash docker.sh server.up $2
elif [[ "$1" == "start" ]]; then
    utils.printer "Start services"
    docker-compose start $2
elif [[ "$1" == "restart" ]]; then
    utils.printer "Restart services"
    docker-compose restart $2
elif [[ "$1" == "stop" ]]; then
    utils.printer "Stop services"
    docker-compose stop $2
elif [[ "$1" == "rm" ]]; then
    utils.printer "Stop && remove services"
    docker-compose stop $2
    docker-compose rm $2
elif [[ "$1" == "bash" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Connect to $2 bash shell"
        docker-compose exec $2 bash
    else
        utils.printer "You should specify the service name: flask | nginx | certbot"
    fi
elif [[ "$1" == "sh" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Connect to $2 bash shell"
        docker-compose exec $2 sh
    else
        utils.printer "You should specify the service name: flask | nginx | certbot"
    fi
elif [[ "$1" == "logs" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Showing logs..."
        if [[ -z "$3" ]]; then
            docker-compose logs -f $2
        else
            docker-compose logs -f --tail=$3 $2
        fi
    else
        utils.printer "You should specify the service name: flask | nginx | certbot"
    fi
elif [[ "$1" == "ps" ]]; then
    utils.printer "Show all running containers"
    docker-compose ps
else
    utils.printer "Params between {} are optional, except {}*"
    utils.printer "Service names: flask | nginx | certbot"
    utils.printer ""
    utils.printer "Usage: docker.sh [deploy|server.up|up|start|restart|stop|rm|sh|bash|logs|machine.[details|create|start|restart|stop|rm|ssh]]"
    echo -e "build {secure}                  --> Build services; \"secure\" parameter is optional for ssl configuration"
    echo -e "deploy                          --> Build and run services"
    echo -e "server.up {secure}              --> Build and run server (nginx) services; \"secure\" parameter is optional for ssl configuration"
    echo -e "up {secure}                     --> Build && deploy services; \"secure\" parameter is optional for ssl configuration"
    echo -e "start {service}                 --> Start services"
    echo -e "restart {service}               --> Restart services"
    echo -e "stop {service}                  --> Stop services"
    echo -e "rm {service}                    --> Stop && remove services"
    echo -e "sh {service}*                   --> Connect to \"service\" shell"
    echo -e "bash {service}*                 --> Connect to \"service\" bash shell"
    echo -e "logs {service}* {n_last_lines}  --> Show \"service\" server logs"
    echo -e "ps                              --> Show all running containers"
    echo -e "machine.[details|create|start|restart|stop|rm|ip|ssh] --> Machine actions"
fi