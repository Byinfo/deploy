#!/bin/bash

# ps auxww
# echo $@
# export

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

	settingsf="/var/www/html/sites/default/settings.php";
	if [ ! -f $settingsf ]; then
		cp -a /var/www/html/sites/default/default.settings.php $settingsf
		if [ ! -z "${DEBUG:-}" ]; then
			echo -e "\$conf['theme_debug'] = TRUE;\n" >> $settingsf
		fi
		echo -e "\$databases['default']['default'] = array(\n" \
			"  'driver' => 'mysql',\n" \
			"  'database' => '${MYSQL_DATABASE}',\n" \
			"  'username' => '${MYSQL_USER}',\n" \
			"  'password' => '${MYSQL_PASSWORD}',\n" \
			"  'host' => '${MYSQL_HOST}',\n" \
			"  'collation' => 'utf8_general_ci',\n" \
			");\n\n" >> $settingsf
		chown "$user:$group" $settingsf;
	fi

fi

exec "$@"
