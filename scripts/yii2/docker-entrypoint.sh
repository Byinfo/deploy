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

	if [ ! -e config/db.php ]; then
		cat <<EOF > config/db.php
		
<?php

return [
    'class' => 'yii\db\Connection',
    'dsn' => 'mysql:host=${MYSQL_HOST};dbname=${MYSQL_DATABASE}',
    'username' => '${MYSQL_USER}',
    'password' => '${MYSQL_PASSWORD}',
    'charset' => 'utf8',
    'enableSchemaCache' => true,
    'schemaCacheDuration' => 3600,
    'schemaCache' => 'cache',
];

EOF

	fi
fi

exec "$@"
