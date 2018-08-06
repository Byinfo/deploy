FROM php:7.0-apache

ARG USERID
ARG GROUPID
ARG PROJECT
ARG APP_TYPE
ARG APACHE_DOCUMENT_ROOT
ENV APACHE_RUN_USER mapped
ENV APACHE_RUN_GROUP mapped

ENV DEBIAN_FRONTEND noninteractive

RUN groupadd -g $GROUPID mapped || groupmod -n mapped $(getent group $GROUPID | cut -d: -f1)
RUN useradd \
      --uid $USERID \
      --gid $GROUPID \
      --home-dir /var/www/html/ \
      mapped

RUN apt-get update
RUN apt-get install -y --no-install-recommends apt-transport-https apt-utils gnupg
RUN apt-get install -y --no-install-recommends \
    libjpeg-dev \
    libpng-dev \
    libgeoip-dev

# NATIVE
RUN docker-php-ext-configure gd --with-png-dir=/usr --with-jpeg-dir=/usr
RUN docker-php-ext-configure mcrypt
RUN docker-php-ext-install -j$(nproc) gd mysqli pdo_mysql opcache mcrypt

# PECL
RUN pecl install geoip-1.1.1
RUN docker-php-ext-enable geoip

RUN { \
    echo 'opcache.memory_consumption=64'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=0'; \
    echo 'opcache.fast_shutdown=1'; \
    echo 'opcache.enable_cli=1'; \
} > /usr/local/etc/php/conf.d/opcache-recommended.ini

RUN { \
    echo 'short_open_tag=Off'; \
    echo 'memory_limit=512M'; \
    echo 'post_max_size=512M'; \
    echo 'upload_max_filesize=512M'; \
    echo 'error_reporting=E_ALL'; \
    echo 'display_errors=On'; \
    echo 'display_startup_errors=On'; \
    echo 'log_errors=On'; \
    echo 'log_errors_max_len=0'; \
    echo 'error_log=/dev/stderr'; \
    echo 'date.timezone = "UTC"'; \
} > /usr/local/etc/php/conf.d/php.ini

RUN a2enmod rewrite expires
RUN sed -ri -e "s!#ServerName .*!ServerName $PROJECT!" /etc/apache2/sites-enabled/000-default.conf
RUN sed -ri -e "s!/var/www/html!${APACHE_DOCUMENT_ROOT}!g" /etc/apache2/apache2.conf /etc/apache2/sites-enabled/*.conf

COPY scripts/${APP_TYPE}/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod a+x /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["apache2-foreground"]

