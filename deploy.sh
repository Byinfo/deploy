#!/bin/bash

set -o pipefail

function get_aws_cli() {
    DOCKERFILE="
FROM debian:stable-slim

ENV DEBIAN_FRONTEND noninteractive

ARG USERID
ARG GROUPID

RUN groupadd -g \$GROUPID mapped || groupmod -n mapped \$(getent group \$GROUPID | cut -d: -f1)
RUN useradd \
      --uid \$USERID \
      --gid \$GROUPID \
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
"
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
    DOCKERFILE="
FROM php:7.0-cli

ENV DEBIAN_FRONTEND noninteractive

ARG USERID
ARG GROUPID

RUN groupadd -g \$GROUPID mapped || groupmod -n mapped \$(getent group \$GROUPID | cut -d: -f1)
RUN useradd \
      --uid \$USERID \
      --gid \$GROUPID \
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
"
    echo "$DOCKERFILE" | docker build -f - \
        --build-arg USERID=$USERID \
        --build-arg GROUPID=$GROUPID \
        . -q
}

function get_latest_db_dump_pantheon {
    FILENAME=${1:-latest.sql.gz}
    TERMINUSID=$(get_terminus_cli)
    docker run --rm -it -e HOME=/tmp -v "$PWD/mysql-init-script/:/mysql-init-script/" \
        $TERMINUSID bash -c "terminus auth:login --machine-token=$PANTHEON_MACHINE_TOKEN && terminus backup:get $PANTHEON_SITE_NAME --element=db --to=/mysql-init-script/latest.sql.gz"
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

function self_update() {
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
    echo "    $0 ( prepare | up | down | status | sync-database | dump-database )"
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
APP_CONTAINER="$PROJECT-app"
APACHE_DOCUMENT_ROOT=/var/www/html/${APP_ROOT%/}

if [[ -z $MYSQL_IMAGE ]]; then
     MYSQL_DOCKERFILE=${MYSQL_DOCKERFILE:-Dockerfile.mysql}
fi

if [[ -z $MYSQL_PORT_MAP ]]; then
     MYSQL_PORT_MAP="'3306:3306'"
fi

if [[ -z $APP_PORT_MAP ]]; then
     APP_PORT_MAP="'80:80'"
fi

if [[ $MYSQL_DOCKERFILE ]]; then
     if [[ ! -e $MYSQL_DOCKERFILE ]]; then
         echo "MYSQL's Dockerfile '$MYSQL_DOCKERFILE' does not exist"
         exit 1
     fi
     MYSQL_IMAGE=$MYSQL_CONTAINER
fi

if [[ $APP_DOCKERFILE ]]; then
     if [[ ! -e $APP_DOCKERFILE ]]; then
         echo "App's Dockerfile '$APP_DOCKERFILE' does not exist"
         exit 1
     fi
     APP_IMAGE=$APP_CONTAINER
else
    if [[ -z $APP_IMAGE ]]; then
        APP_DOCKERFILE="Dockerfile.${APP_TYPE}"
        APP_IMAGE=$APP_CONTAINER
        if [[ ! -e $APP_DOCKERFILE ]]; then
            echo "Unsupported project type '$APP_TYPE'"
            exit 1
        fi
    fi
fi

case $1 in
    prepare)
        self_update "$@"
        if [[ $MYSQL_DOCKERFILE ]]; then
            envsubst \$USERID,\$GROUPID,\$PROJECT,\$APACHE_DOCUMENT_ROOT < $MYSQL_DOCKERFILE | \
                docker build -f - \
                    -t $MYSQL_IMAGE . || exit 1
        fi

        if [[ $APP_DOCKERFILE ]]; then
            envsubst \$USERID,\$GROUPID,\$PROJECT,\$APACHE_DOCUMENT_ROOT < $APP_DOCKERFILE | \
                docker build -f - \
                    -t $APP_IMAGE . || exit 1
        fi

        get_latest_db_dump
        if [[ ! -d webroot/.git ]]; then
            gitcmd clone $REPOSITORY webroot/
        fi
        ;;
    down)
        envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - "$@"
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
        envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - "$@"
        ;;
    status)
        envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - ps
        ;;
    run)
        envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - run --no-deps --rm webapp "${@:2}"
        ;;
    exec)
        envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - exec webapp ${*:2}
        ;;
    git)
        gitcmd -C webroot/ ${*:2}
        ;;
    dump-database)
        if [[ $(docker ps -f id=$(envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - ps -q mysql) -q) != ""  ]]; then
            envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - exec -T mysql mysqldump -uroot $MYSQL_DATABASE
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
    upload)
        if [[ ! -d backup ]]; then
            mkdir backup
        fi 
        FILENAME=$MYSQL_CONTAINER-$(date +%Y-%m-%d.%H:%M:%S).sql.gz
        if [[ $(docker ps -f id=$(envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - ps -q mysql) -q) != ""  ]]; then
            envsubst < docker-compose.yml | docker-compose -p $PROJECT -f - exec -T mysql mysqldump -uroot $MYSQL_DATABASE | gzip - > backup/$FILENAME
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
