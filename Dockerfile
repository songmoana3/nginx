FROM nginx:1.21.4-alpine
RUN apk add --no-cache openssl
RUN rm /etc/nginx/conf.d/default.conf

COPY ./conf.d/default.conf /etc/nginx/conf.d/
COPY options-ssl-nginx.conf /etc/nginx/
COPY entrypoint_nginx.sh /
COPY hsts.conf /etc/nginx/

RUN chmod +x /entrypoint_nginx.sh
EXPOSE 80

CMD ["/entrypoint_nginx.sh"]
