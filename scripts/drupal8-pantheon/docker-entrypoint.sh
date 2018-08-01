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

	settingsf="/var/www/html/sites/default/settings.local.php";
	if [ ! -f $settingsf ]; then
		cp -a /var/www/html/sites/example.settings.local.php $settingsf
		echo -e "\$databases['default']['default'] = array(\n" \
			"  'driver' => 'mysql',\n" \
			"  'database' => '${MYSQL_DATABASE}',\n" \
			"  'username' => '${MYSQL_USER}',\n" \
			"  'password' => '${MYSQL_PASSWORD}',\n" \
			"  'host' => '${MYSQL_HOST}',\n" \
			"  'collation' => 'utf8mb4_general_ci',\n" \
			");\n\n" \
			"\$settings['cache']['bins']['render'] = 'cache.backend.null';\n" \
			"\$settings['cache']['bins']['dynamic_page_cache'] = 'cache.backend.null';\n" \
			"\$settings['cache']['bins']['page'] = 'cache.backend.null';\n" \
			"\$settings['hash_salt'] = \"Dq7Y_ipY3UsSdf23q5VsQuJa2OIjuOicQ_zOumlF4gQsb9Hvh1WW_a5-55IskNO0GibY26aBKQ\";\n\n" >> $settingsf
		chown "$user:$group" $settingsf;
	fi

fi

exec "$@"
