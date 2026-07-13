FROM postgres:16

COPY init.sql /docker-entrypoint-initdb.d/

CMD ["postgres", "-c", "log_statement=all"]