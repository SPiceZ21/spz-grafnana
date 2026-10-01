ARG GRAFANA_BASE_IMAGE=grafana/grafana:11.6.0
FROM ${GRAFANA_BASE_IMAGE}

USER root
RUN apk add --no-cache bash nodejs npm

RUN adduser -D -u 988 -h /home/container container \
    && mkdir -p /home/container /opt/spz-grafana \
    && chown -R container:container /home/container

WORKDIR /opt/spz-grafana
COPY tools/package.json ./package.json
RUN npm install --omit=dev --no-audit --no-fund
COPY tools/server-monitor.mjs tools/track-map-server.mjs tools/prepare-dashboard.mjs ./tools/
COPY provisioning ./provisioning
COPY public ./public
COPY start.sh pterodactyl-entrypoint.sh ./

ENV GF_PATHS_HOME=/usr/share/grafana \
    GF_PATHS_CONFIG=/etc/grafana/grafana.ini \
    GF_PATHS_DATA=/home/container/data \
    GF_PATHS_PLUGINS=/home/container/data/plugins \
    GF_PATHS_PROVISIONING=/opt/spz-grafana/provisioning \
    GF_SERVER_HTTP_ADDR=0.0.0.0 \
    TRACK_MAP_ENABLED=true \
    USER=container \
    HOME=/home/container

USER container
WORKDIR /home/container
ENTRYPOINT []
CMD ["/bin/bash", "/opt/spz-grafana/pterodactyl-entrypoint.sh"]
