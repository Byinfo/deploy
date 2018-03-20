#!/bin/bash

set -euo pipefail

# usage: file_env VAR [DEFAULT]
#    ie: file_env 'XYZ_DB_PASSWORD' 'example'
# (will allow for "$XYZ_DB_PASSWORD_FILE" to fill in the value of
#  "$XYZ_DB_PASSWORD" from a file, especially for Docker's secrets feature)
file_env() {
	local var="$1"
	local fileVar="${var}_FILE"
	local def="${2:-}"
	if [ "${!var:-}" ] && [ "${!fileVar:-}" ]; then
		echo >&2 "error: both $var and $fileVar are set (but are exclusive)"
		exit 1
	fi
	local val="$def"
	if [ "${!var:-}" ]; then
		val="${!var}"
	elif [ "${!fileVar:-}" ]; then
		val="$(< "${!fileVar}")"
	fi
	export "$var"="$val"
	unset "$fileVar"
}

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

	if [ ! -e $APP_ROOT/config.php ]; then
		cat <<EOF > $APP_ROOT/config.php
<?php
// HTTP
define('HTTP_SERVER', 'http://' . \$_SERVER['HTTP_HOST'] .'/');

// HTTPS
define('HTTPS_SERVER', 'http://' . \$_SERVER['HTTP_HOST'] .'/');

// DIR
define('DIR_APPLICATION', '/var/www/html/${APP_ROOT}catalog/');
define('DIR_SYSTEM', '/var/www/html/${APP_ROOT}system/');
define('DIR_IMAGE', '/var/www/html/${APP_ROOT}image/');
define('DIR_LANGUAGE', '/var/www/html/${APP_ROOT}catalog/language/');
define('DIR_TEMPLATE', '/var/www/html/${APP_ROOT}catalog/view/theme/');
define('DIR_CONFIG', '/var/www/html/${APP_ROOT}system/config/');
define('DIR_CACHE', '/var/www/html/${APP_ROOT}system/storage/cache/');
define('DIR_DOWNLOAD', '/var/www/html/${APP_ROOT}system/storage/download/');
define('DIR_LOGS', '/var/www/html/${APP_ROOT}system/storage/logs/');
define('DIR_MODIFICATION', '/var/www/html/${APP_ROOT}system/storage/modification/');
define('DIR_UPLOAD', '/var/www/html/${APP_ROOT}system/storage/upload/');

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '${MYSQL_HOST}');
define('DB_USERNAME', '${MYSQL_USER}');
define('DB_PASSWORD', '${MYSQL_PASSWORD}');
define('DB_DATABASE', '${MYSQL_DATABASE}');
define('DB_PORT', '3306');
define('DB_PREFIX', 'oc_');
EOF
	fi

	if [ ! -e $APP_ROOT/admin/config.php ]; then
		cat <<EOF > $APP_ROOT/admin/config.php
<?php
// HTTP
define('HTTP_SERVER', 'http://' . \$_SERVER['HTTP_HOST'] .'/admin/');
define('HTTP_CATALOG', 'http://' . \$_SERVER['HTTP_HOST'] .'/');

// HTTPS
define('HTTPS_SERVER', 'http://' . \$_SERVER['HTTP_HOST'] .'/admin/');
define('HTTPS_CATALOG', 'http://' . \$_SERVER['HTTP_HOST'] .'/');

// DIR
define('DIR_APPLICATION', '/var/www/html/${APP_ROOT}admin/');
define('DIR_SYSTEM', '/var/www/html/${APP_ROOT}system/');
define('DIR_IMAGE', '/var/www/html/${APP_ROOT}image/');
define('DIR_LANGUAGE', '/var/www/html/${APP_ROOT}admin/language/');
define('DIR_TEMPLATE', '/var/www/html/${APP_ROOT}admin/view/template/');
define('DIR_CONFIG', '/var/www/html/${APP_ROOT}system/config/');
define('DIR_CACHE', '/var/www/html/${APP_ROOT}system/storage/cache/');
define('DIR_DOWNLOAD', '/var/www/html/${APP_ROOT}system/storage/download/');
define('DIR_LOGS', '/var/www/html/${APP_ROOT}system/storage/logs/');
define('DIR_MODIFICATION', '/var/www/html/${APP_ROOT}system/storage/modification/');
define('DIR_UPLOAD', '/var/www/html/${APP_ROOT}system/storage/upload/');
define('DIR_CATALOG', '/var/www/html/${APP_ROOT}catalog/');
define('DIR_ATREX_UPLOAD', '/var/www/html/${APP_ROOT}atrex/');

// DB
define('DB_DRIVER', 'mysqli');
define('DB_HOSTNAME', '${MYSQL_HOST}');
define('DB_USERNAME', '${MYSQL_USER}');
define('DB_PASSWORD', '${MYSQL_PASSWORD}');
define('DB_DATABASE', '${MYSQL_DATABASE}');
define('DB_PORT', '3306');
define('DB_PREFIX', 'oc_');
EOF

	fi
fi


exec "$@"
