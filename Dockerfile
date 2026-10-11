FROM alpine:3.21

RUN apk add --no-cache \
        ca-certificates \
        openssl \
        curl \
        su-exec \
        socat \
        openconnect

COPY ./docker-entrypoint.sh /usr/bin/

# Автоматически удаляем Windows-символы \r из файла перед запуском
RUN sed -i 's/\r$//' /usr/bin/docker-entrypoint.sh \
    && chmod +x /usr/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["openconnect"]
