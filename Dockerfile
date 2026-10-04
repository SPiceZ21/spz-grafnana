# Grafana only: the official image plus this repo's provisioning (one MySQL
# data source, one dashboard). No extra services, nothing else baked in.
ARG GRAFANA_BASE_IMAGE=grafana/grafana:11.6.0
FROM ${GRAFANA_BASE_IMAGE}

USER root
# Pterodactyl runs containers as uid 988 in /home/container.
RUN adduser -D -u 988 -h /home/container container     && mkdir -p /home/container/data     && chown -R container:container /home/container
COPY --chown=container:container provisioning /etc/grafana/provisioning
COPY --chown=container:container start.sh pterodactyl-entrypoint.sh /opt/spz-grafana/

ENV GF_PATHS_DATA=/home/container/data     GF_PATHS_PLUGINS=/home/container/data/plugins     GF_PATHS_PROVISIONING=/etc/grafana/provisioning     GF_SERVER_HTTP_ADDR=0.0.0.0     GF_USERS_ALLOW_SIGN_UP=false     USER=container     HOME=/home/container

USER container
WORKDIR /home/container
ENTRYPOINT []
CMD ["/bin/bash", "/opt/spz-grafana/pterodactyl-entrypoint.sh"]
