#!/bin/bash
mkdir -p /run/php-fpm
sed -i 's/;clear_env = no/clear_env = no/' /etc/php-fpm.d/www.conf
ln -sf /dev/stderr /var/log/php-fpm/error.log
ln -sf /dev/stderr /var/log/php-fpm/www-error.log
php-fpm
httpd -D FOREGROUND
