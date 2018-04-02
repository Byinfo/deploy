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

	if [ ! -z "$(ls -A /var/www/html)" ]; then
		echo "Processing WEBROOT setup.."
		if [ ! -e /var/www/html/sites/default/default.settings.php ]; then
			ls -lah /var/www/html/
			echo "-----------> NO docker.settings.php FOUND         <-----------"
			echo "-----------> Setup /sites/default/settings.php !! <-----------"
		else
			settingsf="/var/www/html/sites/default/settings.php";
			cp -a /var/www/html/sites/default/default.settings.php $settingsf
                        echo -e "\$databases['default']['default'] = array(\n" \
                                "  'driver' => 'mysql',\n" \
                                "  'database' => 'ndcpartner',\n" \
                                "  'username' => 'ndcpartner_user',\n" \
                                "  'password' => 'owj1hJ2EKXyj',\n" \
                                "  'host' => 'mysql',\n" \
                                "  'collation' => 'utf8_general_ci',\n" \
                                ");\n\n" >> $settingsf
		fi
	fi

fi

exec "$@"
