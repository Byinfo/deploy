#!/bin/bash

set -euo pipefail

if [[ "$1" == apache2* ]] || [ "$1" == php-fpm ]; then
	if [ "$(id -u)" = '0' ]; then
		case "$1" in
			apache2*)
				user="${APACHE_RUN_USER:-www-data}"
				group="${APACHE_RUN_GROUP:-www-data}"
				;;
			*) # php-fpm
				user='www-data'
				group='www-data'
				;;
		esac
	else
		user="$(id -u)"
		group="$(id -g)"
	fi
	
	if [ ! -e protected/runtime ]; then
		mkdir protected/runtime && chmod 777 protected/runtime
	fi
	
	if [ ! -e assets ]; then
		mkdir assets && chmod 777 assets
	fi	
	
	if [ ! -e protected/config/db.php ]; then
		cat <<EOF > protected/config/db.php
<?php
return array {
    'connectionString' => 'mysql:host=${MYSQL_HOST};dbname=${MYSQL_DATABASE}',
    'emulatePrepare' => true,   
    'username' => '${MYSQL_USER}',
    'password' => '${MYSQL_PASSWORD}',
    'charset' => 'utf8',
    'enableParamLogging' => true,
};
EOF
	fi
	
	if [ ! -e protected/config/environment.php ]; then
		cat <<EOF > protected/config/environment.php
<?php
// this var will include proper config (main_local.php)

define("YII_ENV", PROD);
EOF
	fi	
fi

exec "$@"
