#!/bin/bash

# Utils functions
. ./../utils.sh

# Create envs vars if don't exist
ENV_FILES=(".env" "meteor/.env" "nginx/site.template" "nginx/site.template.ssl" "nginx/.env" "nginx/nginx.conf" "nginx/renewssl.sh" "nginx/crontab")
utils.check_envs_files "${ENV_FILES[@]}"

# Load environment vars, to use from console, run follow command:
utils.load_environment
utils.load_environment_meteor
utils.load_environment_nginx


# Menu options
if [[ "$1" == "machine.create" ]]; then
    utils.printer "Cheking if remote machine exist..."
    # If machine doesn't exist, create a droplet and provision machine
    if [[ "$MACHINE_DRIVER" == "do" ]]; then
        if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
            utils.printer "Starting machine if it's off..."
            docker-machine start $MACHINE_NAME
            utils.printer "Creating machine using \"do\" driver..."
            docker-machine create --driver digitalocean --digitalocean-access-token $DO_ACCESS_TOKEN --digitalocean-image $DO_IMAGE --digitalocean-size $DO_SIZE $MACHINE_NAME
            utils.printer "Machine created at: $(docker-machine ip $MACHINE_NAME)"
        else
            utils.printer "Starting machine if it's off using \"aws\" driver..."
            docker-machine start $MACHINE_NAME
            utils.printer "Machine already exist at: $(docker-machine ip $MACHINE_NAME)"
        fi
    elif [[ "$MACHINE_DRIVER" == "aws" ]]; then
        if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
            utils.printer "Creating machine using \"aws\" driver..."
            docker-machine create --driver amazonec2 --amazonec2-access-key $AWS_ACCESS_KEY_ID --amazonec2-secret-key $AWS_SECRET_ACCESS_KEY --amazonec2-vpc-id $AWS_VPC_ID --amazonec2-region $AWS_DEFAULT_REGION --amazonec2-instance-type $AWS_INSTANCE_TYPE --amazonec2-root-size $AWS_ROOT_SIZE --amazonec2-ssh-user $AWS_SSH_USER $MACHINE_NAME
            utils.printer "Machine created at: $(docker-machine ip $MACHINE_NAME)"
        else
            utils.printer "Starting machine if it's off using \"aws\" driver..."
            docker-machine start $MACHINE_NAME
            utils.printer "Machine already exist at: $(docker-machine ip $MACHINE_NAME)"
        fi
    elif [[ "$MACHINE_DRIVER" == "virtualbox" ]]; then
        if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
            utils.printer "Creating machine using \"virtualbox\" driver..."
            docker-machine create -d virtualbox $MACHINE_NAME
            utils.printer "Machine created at: $(docker-machine ip $MACHINE_NAME)"
        else
            utils.printer "Starting machine if it's off using \"virtualbox\" driver..."
            docker-machine start $MACHINE_NAME
            utils.printer "Machine already exist at: $(docker-machine ip $MACHINE_NAME)"
        fi
    elif [[ "$MACHINE_DRIVER" == "generic" ]]; then
        if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
            utils.printer "Machine doesn't exist."
        else
            utils.printer "Machine already exist at: $(docker-machine ip $MACHINE_NAME)"
        fi
    fi
elif [[ "$1" == "build" ]]; then
    if [[ "$2" == "secure" ]]; then
        utils.printer "Settting default.conf based on site.template.ssl..."
        cp nginx/site.template.ssl nginx/default.conf
    else
        utils.printer "Settting default.conf based on site.template..."
        cp nginx/site.template nginx/default.conf
    fi
    utils.printer "Load settings.json in meteor/.env file"
    sed -i /METEOR_SETTINGS/c\METEOR_SETTINGS="$(json-minify ../../settings.json)" meteor/.env
    utils.printer "Copy Dokerfile && google-cloud.json into docker-compose build context..."
    PWD_PATH=$(pwd)
    mkdir -p ../../../${SERVICE_METEOR_BUILD_CONTEXT}
    cp meteor/Dockerfile ../../../${SERVICE_METEOR_BUILD_CONTEXT}/Dockerfile
    cd ../..
    utils.printer "Copy custom files to build context..."
    utils.copy_meteor_build_files
    utils.printer "Meteor build"
    meteor npm install
    meteor build ../${SERVICE_METEOR_BUILD_CONTEXT} --architecture os.linux.x86_64
    mv ../${SERVICE_METEOR_BUILD_CONTEXT}/"$(utils.current_folder_name)".tar.gz ../${SERVICE_METEOR_BUILD_CONTEXT}/bundle.tar.gz
    cd $PWD_PATH
    utils.printer "Building images"
    docker-compose -f docker-compose.build.yaml build
elif [[ "$1" == "push" ]]; then
    utils.printer "Tagging images meteor..."
    utils.printer "${COMPOSE_PROJECT_NAME}_${SERVICE_METEOR_BUILD_NAME} --> ${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_METEOR_BUILD_NAME}-${SERVICE_METEOR_BUILD_TAG_CALC}"
    docker tag "${COMPOSE_PROJECT_NAME}_${SERVICE_METEOR_BUILD_NAME}" "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_METEOR_BUILD_NAME}-${SERVICE_METEOR_BUILD_TAG_CALC}"
    utils.printer "Tagging images nginx..."
    utils.printer "${COMPOSE_PROJECT_NAME}_${SERVICE_NGINX_BUILD_NAME} --> ${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_NGINX_BUILD_NAME}-${SERVICE_NGINX_BUILD_TAG_CALC}"
    docker tag "${COMPOSE_PROJECT_NAME}_${SERVICE_NGINX_BUILD_NAME}" "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_NGINX_BUILD_NAME}-${SERVICE_NGINX_BUILD_TAG_CALC}"
    if [[ "${CONTAINER_REGISTRY_SERVICE}" == "dockerhub" ]]; then
        utils.printer "Loggin in DockerHub"
        docker login -u ${CONTAINER_REGISTRY_USER} -p ${CONTAINER_REGISTRY_PASS}
    elif [[ "${CONTAINER_REGISTRY_SERVICE}" == "aws" ]]; then
        $(aws ecr get-login --no-include-email --region ${AWS_DEFAULT_REGION})
    fi
    utils.printer "Push images..."
    docker push "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_METEOR_BUILD_NAME}-${SERVICE_METEOR_BUILD_TAG_CALC}"
    docker push "${CONTAINER_REGISTRY_PREFIX}/${CONTAINER_REGISTRY_REPOSITORY_NAME}:${COMPOSE_PROJECT_NAME}-${SERVICE_NGINX_BUILD_NAME}-${SERVICE_NGINX_BUILD_TAG_CALC}"
elif [[ "$1" == "deploy" ]]; then
    utils.printer "Pulling images"
    docker-compose $(docker-machine config $MACHINE_NAME) pull
    utils.printer "Deploying services"
    docker-compose $(docker-machine config $MACHINE_NAME) up -d mongodb meteor
    utils.printer "Your application is deployed in: $(docker-machine ip $MACHINE_NAME)"
elif [[ "$1" == "server.up" ]]; then
    if [[ "$2" == "secure" ]]; then
        utils.printer "Set nginx service renewssl vars..."
        utils.nginx_renewssl_vars
        utils.printer "Stopping nginx machine if it's running..."
        docker-compose $(docker-machine config $MACHINE_NAME) stop nginx
        utils.printer "Creating letsencrypt certifications files..."
        docker-compose $(docker-machine config $MACHINE_NAME) up certbot
        utils.printer "Setting up cron job for auto renew ssl..."
        CRONPATH=/opt/crons/${COMPOSE_PROJECT_NAME}
        docker-machine ssh $MACHINE_NAME sudo mkdir -p $CRONPATH
        docker-machine scp nginx/renewssl.sh $MACHINE_NAME:$CRONPATH/renewssl.sh
        docker-machine ssh $MACHINE_NAME sudo chmod +x $CRONPATH/renewssl.sh
        docker-machine ssh $MACHINE_NAME sudo touch $CRONPATH/renewssl.logs
        docker-machine scp nginx/crontab $MACHINE_NAME:$CRONPATH/crontab
        docker-machine ssh $MACHINE_NAME sudo crontab $CRONPATH/crontab
    else
        utils.printer "Settting default.conf based on site.template..."
        cp nginx/site.template nginx/default.conf
    fi
    utils.printer "Starting nginx machine..."
    docker-compose $(docker-machine config $MACHINE_NAME) up -d nginx
    docker-compose $(docker-machine config $MACHINE_NAME) restart nginx
elif [[ "$1" == "up" ]]; then
    # Create machine
    bash docker.machine.sh machine.create
    # Build meteor && docker images
    bash docker.machine.sh build $2
    # Pushing images to docker hub
    bash docker.machine.sh push
    # Deploying services to remote machine server
    bash docker.machine.sh deploy
    # Set server configuration
    bash docker.machine.sh server.up $2
elif [[ "$1" == "start" ]]; then
    utils.printer "Start services"
    docker-compose $(docker-machine config $MACHINE_NAME) start $2
elif [[ "$1" == "restart" ]]; then
    utils.printer "Restart services"
    docker-compose $(docker-machine config $MACHINE_NAME) restart $2
elif [[ "$1" == "stop" ]]; then
    utils.printer "Stop services"
    docker-compose $(docker-machine config $MACHINE_NAME) stop $2
elif [[ "$1" == "rm" ]]; then
    utils.printer "Stop && remove services"
    docker-compose $(docker-machine config $MACHINE_NAME) stop $2
    docker-compose $(docker-machine config $MACHINE_NAME) rm $2
elif [[ "$1" == "bash" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Connect to $2 bash shell"
        docker-compose $(docker-machine config $MACHINE_NAME) exec $2 bash
    else
        utils.printer "You should specify the service name: mongodb | meteor | nginx | certbot"
    fi
elif [[ "$1" == "sh" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Connect to $2 bash shell"
        docker-compose $(docker-machine config $MACHINE_NAME) exec $2 sh
    else
        utils.printer "You should specify the service name: mongodb | meteor | nginx | certbot"
    fi
elif [[ "$1" == "logs" ]]; then
    if [[ ! -z "$2" ]]; then
        utils.printer "Showing logs..."
        if [[ -z "$3" ]]; then
            docker-compose $(docker-machine config $MACHINE_NAME) logs -f $2
        else
            docker-compose $(docker-machine config $MACHINE_NAME) logs -f --tail=$3 $2
        fi
    else
        utils.printer "You should specify the service name: mongodb | meteor"
    fi
elif [[ "$1" == "ps" ]]; then
    utils.printer "Show all running containers"
    docker-compose $(docker-machine config $MACHINE_NAME) ps
elif [[ "$1" == "machine.details" ]]; then
    utils.printer "Searching for machine details..."
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Machine driver: $MACHINE_DRIVER"
        utils.printer "Machine name: $MACHINE_NAME"
        utils.printer "Machine ip: $(docker-machine ip $MACHINE_NAME)"
    fi
elif [[ "$1" == "machine.start" ]]; then
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Power on machine..."
        docker-machine rm $MACHINE_NAME
    fi
elif [[ "$1" == "machine.restart" ]]; then
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Restarting on machine..."
        docker-machine restart $MACHINE_NAME
    fi
elif [[ "$1" == "machine.stop" ]]; then
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Power off machine..."
        docker-machine stop $MACHINE_NAME
    fi
elif [[ "$1" == "machine.rm" ]]; then
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Power off machine..."
        docker-machine stop $MACHINE_NAME
        utils.printer "Removing machine..."
        docker-machine rm $MACHINE_NAME
    fi
elif [[ "$1" == "machine.ssh" ]]; then
    if [[ "$MACHINE_NAME" != $(docker-machine ls -q | grep "^$MACHINE_NAME$") ]]; then
        utils.printer "Machine doesn't exist"
    else
        utils.printer "Conecting via ssh to \"$MACHINE_NAME\" machine..."
        docker-machine ssh $MACHINE_NAME
    fi
else
    utils.printer "Params between {} are optional, except {}*"
    utils.printer "Service names: mongodb | meteor | nginx | certbot"
    utils.printer ""
    utils.printer "Usage: docker.machine.sh [deploy|server.up|up|start|restart|stop|rm|sh|bash|logs|machine.[details|create|start|restart|stop|rm|ssh]]"
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