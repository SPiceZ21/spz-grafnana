# SPZ Race Analytics (Grafana)

Grafana dashboard for SPZ race results, player/race analytics, poll history, crash investigation, FiveM server health, and GTA V track visualization. It supports local Docker Compose and a **single-container Pterodactyl deployment**. Pterodactyl runs Grafana, the FiveM health monitor, and the optional track-map HTTP server in one server/container. Race MySQL and Health MySQL remain external.

## Pterodactyl deployment (one server/container)

### 1. Prepare the external databases

- Keep Race MySQL separate from the Health database. Create/use a Race MySQL account with `SELECT` only; Grafana does not modify race tables.
- Create the Health database/schema on an external MySQL/MariaDB service. Do not create a database service in the Pterodactyl container.
- Give the monitor Health account `CREATE`, `ALTER`, `INSERT`, and `SELECT` privileges on the Health schema. The monitor creates/updates only `server_health_checks` and inserts samples there.
- For best separation, give Grafana a different Health account with `SELECT` only. If `GF_DATABASE_HEALTH_*` values are blank, the startup script derives them from `HEALTH_DB_*`.
- Allow network access from the Pterodactyl node to both databases and the FiveM `/dynamic.json` endpoint.

Migration files `018_grafana_poll_history.sql` and `019_race_incidents.sql` are not run by this deployment. They are unrelated to the separate server-health history table.

### 2. Build and publish the one-container image

Build from this directory and publish the image to a registry the Pterodactyl Wings node can pull:

```sh
docker build -t ghcr.io/YOUR_ACCOUNT/spz-grafana-pterodactyl:1.0.0 .
docker push ghcr.io/YOUR_ACCOUNT/spz-grafana-pterodactyl:1.0.0
```

The image extends the official Grafana image with Node.js, the `mysql2` dependency, the track-map server, and the startup supervisor. It does not contain or start MySQL/MariaDB. Publish the image as public or configure registry credentials on the Wings node.

### 3. Import the Egg and create one server

1. In the Pterodactyl Admin Panel, import [pterodactyl-egg.json](pterodactyl-egg.json) as an Egg.
2. Replace the Egg's placeholder image `ghcr.io/your-org/spz-grafana-pterodactyl:latest` with the image tag you published.
3. Create **one** Pterodactyl server with this Egg and the custom image. Assign one primary TCP allocation for Grafana. The Egg startup command uses Pterodactyl's allocated `{{SERVER_PORT}}` and sets `GF_SERVER_HTTP_ADDR=0.0.0.0` and `GF_SERVER_HTTP_PORT` to that allocation.
4. To serve the map, assign one additional TCP allocation, set `TRACK_MAP_ENABLED=true`, set `TRACK_MAP_PORT` to that exact allocation, and set `TRACK_MAP_PUBLIC_URL` to the address browsers can reach, including the port (for example `http://node.example.net:18091`). If Grafana is served over HTTPS, expose the map through an HTTPS reverse proxy too, to avoid browser mixed-content blocks. Disable the map and omit its allocation if not needed.
5. Fill the Egg variables below. Keep credentials private and use unique production passwords.
6. Start the server. Grafana is the supervised foreground service; the Egg stop action sends SIGINT. The startup script forwards shutdown to Grafana, monitor, and map service and waits for them to exit.

### 4. Pterodactyl environment variables

| Purpose | Variables |
| --- | --- |
| Grafana primary allocation | `SERVER_PORT` is supplied by Pterodactyl. Optional override: `GF_SERVER_HTTP_ADDR` (defaults to `0.0.0.0`) and `GF_SERVER_HTTP_PORT` (defaults to `SERVER_PORT`). |
| Grafana admin | `GF_SECURITY_ADMIN_USER`, `GF_SECURITY_ADMIN_PASSWORD` |
| Read-only Race MySQL datasource | `SPZ_DB_HOST`, `SPZ_DB_NAME`, `SPZ_DB_USER`, `SPZ_DB_PASSWORD` |
| FiveM status polling | `FIVEM_HOST`, `FIVEM_PORT`, `HEALTH_POLL_SECONDS` |
| Health writer for monitor | `HEALTH_DB_HOST`, `HEALTH_DB_PORT`, `HEALTH_DB_NAME`, `HEALTH_DB_USER`, `HEALTH_DB_PASSWORD` |
| Grafana Health datasource | `GF_DATABASE_HEALTH_HOST`, `GF_DATABASE_HEALTH_NAME`, `GF_DATABASE_HEALTH_USER`, `GF_DATABASE_HEALTH_PASSWORD` |
| Optional map allocation | `TRACK_MAP_ENABLED`, `TRACK_MAP_PORT`, `TRACK_MAP_PUBLIC_URL` |

Health database fields accept the `GF_DATABASE_HEALTH_*` settings as defaults. Set `HEALTH_DB_*` to an account that can create/alter and insert; set `GF_DATABASE_HEALTH_*` to a separate read-only account for Grafana. The datasource host accepts `host:port`; the monitor also supports a separate host and port.

### Runtime paths inside the Pterodactyl server

- Grafana’s persistent SQLite database and provisioned dashboard copy: `/home/container/data/`
- Required dashboard file: `/home/container/data/dashboards/spz-race-analytics.json`
- Grafana provisioning source: `/opt/spz-grafana/provisioning/`
- Track map source files: `/opt/spz-grafana/public/`
- Runtime monitor, static map server, and supervisor: `/opt/spz-grafana/tools/` and `/opt/spz-grafana/start.sh`

The Pterodactyl server disk backs `/home/container/data`, so Grafana state and the dashboard survive server restarts. The monitor history itself is stored in the external Health database.

## Local Docker Compose development

Compose remains a local development option and may use multiple local application containers. Race and Health databases are configured as external services; Compose does not create a database container. Copy `.env.example` to `.env`, set separate reader/writer accounts and external database endpoints, then run `docker compose up -d`. The local map defaults to port 8090; set `TRACK_MAP_PORT` to change it. Grafana is on port 3000 by default.

## Health monitor behavior

`tools/server-monitor.mjs` requests `http://FIVEM_HOST:FIVEM_PORT/dynamic.json` every `HEALTH_POLL_SECONDS` (default 30 seconds). It records UTC check time, interval, reachability, HTTP latency, `players_online`, `max_players`, and an error string in `server_health_checks`. The monitor retries after database/schema failures and creates the table automatically when the pre-created external Health schema is available. Uptime and estimated downtime start accumulating only after deployment; they are based on the sampling interval and cannot be backfilled. This endpoint check does not measure server tick rate or guarantee a complete game-client handshake.

## Dashboard and map contents

- Race activity, duration, DNF rate, track/class mix, result history, and leaderboards
- Player career details, race-by-race results, pace, and crash trends
- FiveM reachability, 24-hour uptime, estimated downtime, response latency, players/capacity, and failed checks
- Track route GeoMap and an optional interactive route explorer
- Crash map, crash heatmap, and incident detail panels (incident data requires the separate project migration and resource rollout)
- Poll analytics (poll history also requires the separate project migration)

The route explorer and Grafana's **SPZ Track Routes** GeoMap use Rockstar's GTA V tile URL `https://s.rsg.sc/sc/images/games/GTAV/map/game/{z}/{x}/{y}.jpg`. The Pterodactyl startup helper rewrites localhost map URLs in the provisioned dashboard to `TRACK_MAP_PUBLIC_URL`. `tools/export_tracks.py` generates `public/tracks.json` and `public/tracks.geojson` from `spz-races/data/tracks.lua`; rerun it after track definitions change and rebuild/publish the Pterodactyl image.

## Files used at runtime

```text
Dockerfile                              Build the single Pterodactyl image
start.sh                               Validate config, prepare paths, launch/supervise all processes
tools/server-monitor.mjs               FiveM status poller and external Health DB writer
tools/track-map-server.mjs              Optional static HTTP server with CORS for Grafana GeoJSON
tools/prepare-dashboard.mjs             Copies/rewrites the provisioned dashboard for the public map URL
tools/package.json                      mysql2 runtime dependency
provisioning/datasources/mysql.yml      Separate Race and Health MySQL datasources
provisioning/dashboards/provider.yml    File provider rooted at /home/container/data/dashboards
provisioning/dashboards/spz-race-analytics.json  Dashboard source copied to the provider directory
public/index.html                        Interactive map web app
public/tracks.json                       Interactive map route data
public/tracks.geojson                    Grafana route overlay data
pterodactyl-egg.json                     Importable Pterodactyl Egg definition
pterodactyl-entrypoint.sh                Pterodactyl environment/port entrypoint
docker-compose.yml                       Optional local development stack; not used on Pterodactyl
nginx.conf                               Local Compose map-server CORS config; not used by Pterodactyl
```

The Pterodactyl image copies the runtime files into `/opt/spz-grafana`. Only Grafana state and the installed dashboard are written to `/home/container/data`. No race migration is executed by the Egg or startup script.
