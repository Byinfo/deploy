#!/bin/bash

set -o pipefail

function get_aws_cli() {
    DOCKERFILE='
FROM debian:stable-slim

ENV DEBIAN_FRONTEND noninteractive

ARG USERID
ARG GROUPID

RUN groupadd -g $GROUPID mapped || groupmod -n mapped $(getent group $GROUPID | cut -d: -f1)
RUN useradd \
      --uid $USERID \
      --gid $GROUPID \
      --home-dir / \
      mapped

WORKDIR /

RUN apt-get update && apt-get install -y \
    python \
    wget
    
RUN wget https://bootstrap.pypa.io/get-pip.py && python get-pip.py

RUN pip install --upgrade pip && \
    pip install awscli

USER mapped
'
    echo "$DOCKERFILE" | docker build -f - \
        --build-arg USERID=$USERID \
        --build-arg GROUPID=$GROUPID \
        . -q
}

function get_git_cli() {
    REPOSITORY_KEY=$(echo "$1" | perl -pe 's/\n/\\n/g')

    DOCKERFILE="
FROM debian:stable-slim

ENV DEBIAN_FRONTEND noninteractive

ARG USERID
ARG GROUPID

RUN groupadd -g \$GROUPID mapped || groupmod -n mapped \$(getent group \$GROUPID | cut -d: -f1)
RUN useradd \
      --uid \$USERID \
      --gid \$GROUPID \
      --home-dir /git \
      mapped

WORKDIR /git

# install git
RUN apt-get -y update && apt-get -y install git

RUN echo -ne \"${REPOSITORY_KEY}\" > /id_rsa
RUN chown mapped: /id_rsa
RUN chmod 0600 /id_rsa

USER mapped
ENTRYPOINT [\"git\"]
"

    echo "$DOCKERFILE" | docker build -f - \
        --build-arg USERID=$USERID \
        --build-arg GROUPID=$GROUPID \
        . -q
}

function get_terminus_cli() {
    DOCKERFILE='
FROM php:7.0-cli

ENV DEBIAN_FRONTEND noninteractive

ARG USERID
ARG GROUPID

RUN groupadd -g $GROUPID mapped || groupmod -n mapped $(getent group $GROUPID | cut -d: -f1)
RUN useradd \
      --uid $USERID \
      --gid $GROUPID \
      --home-dir / \
      mapped

WORKDIR /

RUN apt-get update
RUN apt-get install -y \
    curl \
    unzip \
    ssh

RUN curl -O https://raw.githubusercontent.com/pantheon-systems/terminus-installer/master/builds/installer.phar && php installer.phar install

USER mapped
'

    echo "$DOCKERFILE" | docker build -f - \
        --build-arg USERID=$USERID \
        --build-arg GROUPID=$GROUPID \
        . -q
}

function get_latest_db_dump_pantheon {
    FILENAME=${1:-latest.sql.gz}
    TERMINUSID=$(get_terminus_cli)
    docker run --rm -it -e HOME=/tmp -v "$PWD/mysql-init-script/:/mysql-init-script/" \
        $TERMINUSID bash -c "terminus auth:login --machine-token=$PANTHEON_MACHINE_TOKEN && echo \"Downloading database ...\" && terminus -v backup:get $PANTHEON_SITE_NAME --element=db --to=/mysql-init-script/latest.sql.gz"
}

function get_latest_files_from_pantheon {
    FILENAME=${1:-latest.tgz}
    if [[ ! -f remote-files/latest.tgz ]]; then
        TERMINUSID=$(get_terminus_cli)
        docker run --rm -it -e HOME=/tmp -v "$PWD/remote-files/:/remote-files/" \
            $TERMINUSID bash -c "terminus auth:login --machine-token=$PANTHEON_MACHINE_TOKEN && echo \"Downloading files ...\" && terminus -v backup:get $PANTHEON_SITE_NAME --element=files --to=/remote-files/latest.tgz"
    fi
}

function get_latest_db_dump_aws() {
    FILENAME=${1:-latest.sql.gz}
    AWSID=$(get_aws_cli)
    echo "Downloading database dump from AWS..."
    docker run --rm -it -v "$PWD/mysql-init-script/:/mysql-init-script/" \
         -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
         -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
         -e AWS_DEFAULT_REGION=$AWS_REGION \
         $AWSID \
             aws s3 cp s3://$BUCKET/$FILENAME /mysql-init-script/$FILENAME
}

function get_latest_db_dump {
    if [[ ! -f mysql-init-script/latest.sql.gz ]]; then
        if [[ ! -d mysql-init-script/ ]]; then
            mkdir mysql-init-script/
        fi
        if [[ $BUCKET ]]; then
            get_latest_db_dump_aws
        elif [[ $PANTHEON_SITE_NAME ]]; then
            get_latest_db_dump_pantheon
        fi
    fi
}

function upload_dump() {
    BUCKET=$1
    FILENAME=$2
    AWSCLI=$(get_aws_cli)
    echo "Uploading $FILENAME to AWS..."

    docker run --rm -it -v "$PWD/backup/:/backup/" \
             -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
             -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
             -e AWS_DEFAULT_REGION=$AWS_REGION \
             $AWSCLI \
                 aws s3 cp /backup/$FILENAME s3://$BUCKET/$FILENAME

    docker run --rm -it -v "$PWD/backup/:/backup/" \
             -e AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID \
             -e AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY \
             -e AWS_DEFAULT_REGION=$AWS_REGION \
             $AWSCLI \
                 aws s3 cp /backup/$FILENAME s3://$BUCKET/latest.sql.gz
}

function gitcmd() {
    if [[ $REPOSITORY_KEY != "" ]]; then
        GIT=$(get_git_cli "$REPOSITORY_KEY")
        docker run -ti --rm -v $PWD:/git -e GIT_SSH_COMMAND='ssh -o "StrictHostKeyChecking no" -o "UserKnownHostsFile /dev/null" -i /id_rsa' $GIT "$@"
    else
        git "$@"
    fi
}

function extract_remote_files() {
    DIR=$1
    STRIP=${2:-1}
    if [[ -f remote-files/latest.tgz ]] && [[ $DIR ]] && [[ -d webroot/$DIR || -d $(dirname webroot/$DIR) ]]; then
        mkdir -p webroot/$DIR
        tar xf remote-files/latest.tgz -C webroot/$DIR --strip-components=$STRIP
    fi
}

function self_update() {
    return
    # self-update
    echo "Checking for a new version of me..."
    git fetch
    if [[ -n $(git diff --name-only origin/master) ]]; then
        echo "Found a new version of me, updating..."
        git reset --hard origin/master
        echo "Restarting..."
        exec "$0" "$@"
        exit 1
    fi
}

function display_usage {
    echo "Usage:"
    echo "    $0 ( prepare | up | down | status | sync-database | sync-files | dump-database )"
    exit 1;
}

set -a

USERID=$(id -u)
GROUPID=$(id -g)

if [[ $USERID == "0" ]]; then
    echo "Running as root is not supported. Please run the following command to add user to the docker group:"
    echo "    \$ sudo usermod -aG docker \$USER"
    exit 1;
fi


source ./config

MYSQL_CONTAINER="$PROJECT-mysql"
MYSQL_IMAGE=$MYSQL_CONTAINER
MYSQL_DOCKERFILE=${MYSQL_DOCKERFILE:-Dockerfile.mysql}

APP_CONTAINER="$PROJECT-app"
APP_IMAGE=$APP_CONTAINER
APP_DOCKERFILES=("Dockerfile.app")
if [[ -e "Dockerfile.${APP_TYPE}" ]]; then
    APP_DOCKERFILES+=("Dockerfile.${APP_TYPE}")
fi
APACHE_DOCUMENT_ROOT=/var/www/html/${APP_ROOT%/}

DOCKER_COMPOSE_ARGS=("-f" "docker-compose.yml")

if [[ $MYSQL_PORT_MAP ]]; then
     DOCKER_COMPOSE_ARGS+=("-f" "docker-compose-mysql.yml")
fi

if [[ $APP_PORT_MAP ]]; then
     DOCKER_COMPOSE_ARGS+=("-f" "docker-compose-app.yml")
fi

case $1 in
    prepare)
        self_update "$@"

        if [[ $MYSQL_DOCKERFILE ]]; then
            docker build \
                --build-arg USERID=$USERID \
                --build-arg GROUPID=$GROUPID \
                -f $MYSQL_DOCKERFILE \
                -t $MYSQL_IMAGE . || exit 1
        fi

        cat ${APP_DOCKERFILES[@]} | docker build \
            --build-arg USERID=$USERID \
            --build-arg GROUPID=$GROUPID \
            --build-arg PROJECT=$PROJECT \
            --build-arg APP_TYPE=$APP_TYPE \
            --build-arg APACHE_DOCUMENT_ROOT=$APACHE_DOCUMENT_ROOT \
            -f - \
            -t $APP_IMAGE . || exit 1

        get_latest_db_dump

        if [[ $PANTHEON_SITE_NAME ]] && [[ $FILES_DIR ]]; then
            get_latest_files_from_pantheon
        fi

        if [[ ! -d webroot/.git ]]; then
            gitcmd clone --recurse-submodules $REPOSITORY webroot/
            (cd webroot/ && gitcmd submodule foreach git checkout master)
        fi
        extract_remote_files $FILES_DIR
        ;;
    down)
        docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} $@
        ;;
    up)
        self_update "$@"
        if [[ ! -d data/db ]]; then
            mkdir -p data/db/
        fi
        if [[ ! -d log/apache2 ]]; then
             mkdir -p log/apache2
        fi
        if [[ ! -d log/mysql ]]; then
             mkdir -p log/mysql
        fi

        touch log/apache2/access.log
        touch log/apache2/error.log
        touch log/mysql/error.log
        if [[ ! -d webroot/.git ]]; then
            echo "Content in your webroot is not tracked by git"
        fi
        docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} $@
        ;;
    status)
        docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} ps
        ;;
    run)
        docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} run --no-deps --rm webapp "${@:2}"
        ;;
    exec)
        docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} exec webapp ${*:2}
        ;;
    git)
        gitcmd -C webroot/ ${*:2}
        ;;
    dump-database)
        if [[ $(docker ps -f id=$(docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} ps -q mysql) -q) != ""  ]]; then
            docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} exec -T mysql mysqldump -uroot $MYSQL_DATABASE
        else
            echo "MYSQL container is not running"
            exit 1
        fi
        ;;
    sync-database)
        rm -rf data/
        rm -rf mysql-init-script/
        get_latest_db_dump
        ;;
    sync-files)
        if [[ $PANTHEON_SITE_NAME ]] && [[ $FILES_DIR ]]; then
            rm -rf remote-files/
            get_latest_files_from_pantheon
            extract_remote_files $FILES_DIR
        else
            echo "File sync is supported for pantheon.io only"
            exit 1;
        fi
        ;;
    upload)
        if [[ ! -d backup ]]; then
            mkdir backup
        fi 
        FILENAME=$MYSQL_CONTAINER-$(date +%Y-%m-%d.%H:%M:%S).sql.gz
        if [[ $(docker ps -f id=$(docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} ps -q mysql) -q) != ""  ]]; then
            docker-compose -p $PROJECT ${DOCKER_COMPOSE_ARGS[@]} exec -T mysql mysqldump -uroot $MYSQL_DATABASE | gzip - > backup/$FILENAME
        else
            echo "MYSQL container is not running"
            exit 1
        fi
        upload_dump $BUCKET $FILENAME
        ;;
    clean)
        cat .gitignore | grep -v 'webroot' | sed -e 's#^/#.//#' | xargs rm -rf
        ;;
    realclean)
        cat .gitignore | sed -e 's#^/#./#' | xargs rm -rf
        ;;
    *)
        display_usage
        ;;
esac
