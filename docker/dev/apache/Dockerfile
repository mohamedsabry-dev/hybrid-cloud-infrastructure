FROM rockylinux/rockylinux:10

RUN dnf install -y httpd php-fpm php-pgsql && dnf clean all

COPY index.php /var/www/webstore/

COPY httpd-app.conf /etc/httpd/conf/httpd.conf

COPY start.sh /start.sh

RUN chmod +x /start.sh 

CMD ["/start.sh"]