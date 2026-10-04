# SPZ Server & Race Analytics (Grafana)

Grafana only. One data source, the SPZ race database (the same `spzcore`
MariaDB the FiveM server uses), and one provisioned dashboard. No extra
services, monitors or map servers.

Every table it reads is created by `spz-core` migrations and filled by the
server resources (mostly `spz-analytics`), so all you deploy here is Grafana.

## Dashboard sections

| Section | Tables |
|---|---|
| Overview | `race_sessions`, `race_results` |
| Server: players online by activity, frame time, ping, entity counts, starts and resource events | `server_snapshots`, `server_events` |
| Players: active players, new players, sessions, playtime by mode, peak hours, disconnects, connections, load time | `daily_player_stats`, `player_sessions`, `player_activity`, `connection_attempts` |
| Race activity | `race_sessions`, `race_results` |
| Race funnel & engine: queue → start → finish, engine failures, time per race phase | `race_queue_events`, `race_engine_events` |
| Track records & pace, lap pace per track | `track_records`, `race_laps` |
| Cars & performance: car win rate, rental vs owned, FPS and ping per track, DNF rate by ping, most driven cars | `race_entries`, `vehicle_usage` |
| Player details, iRating history, promotions & demotions | `race_results`, `player_rating_history` |
| Crash investigation (GTA V map tiles load from Rockstar's site) | `race_incidents` |
| Poll analytics | `race_poll_runs`, `race_poll_options` |
| Economy | `daily_credit_balances` |
| Admin & features | `admin_actions`, `feature_usage` |

Filters at the top: track, class, track type, player.

## Database account

Give Grafana its own **SELECT-only** user on the race database:

```sql
CREATE USER 'grafana_reader'@'%' IDENTIFIED BY 'a-strong-password';
GRANT SELECT ON spzcore.* TO 'grafana_reader'@'%';
```

## Environment

| Variable | Meaning |
|---|---|
| `GF_SECURITY_ADMIN_USER` / `GF_SECURITY_ADMIN_PASSWORD` | Grafana admin login |
| `SPZ_DB_HOST` | `host:port` of the race database |
| `SPZ_DB_NAME` | database name (e.g. `spzcore`) |
| `SPZ_DB_USER` / `SPZ_DB_PASSWORD` | the SELECT-only account |

## Run with Docker Compose

```sh
cp .env.example .env    # fill it in
docker compose up -d
```

Grafana is on port 3000. The dashboard is in the **SPZ** folder.

## Run on Pterodactyl

1. Build and push the image: `docker build -t ghcr.io/YOU/spz-grafana:1.1.0 . && docker push ghcr.io/YOU/spz-grafana:1.1.0`
2. Import `pterodactyl-egg.json`, set its Docker image to your tag.
3. Create one server with one allocation (Grafana's port), fill the six variables, start.

Grafana's own data (users, preferences) lives in `/home/container/data` on the
server's disk. The dashboard and data source are re-provisioned from the image
on every start, so edit `provisioning/` and rebuild to change them.
