# SPZ Race Analytics (Grafana)

This folder contains a provisioned Grafana dashboard, MySQL datasource, a read-only track map explorer, and the SQL migration for persistent poll history.

## Start Grafana

1. Copy `.env.example` to `.env` and set the MySQL connection values. Use a MySQL account with `SELECT` access to the SPZ database.
2. Run `docker compose up -d` from this folder.
3. Open <http://localhost:3000> and sign in with the Grafana admin credentials from `.env`.
4. Open **SPZ Race Analytics** in the provisioned dashboards. The **Track Map Explorer** link opens the poll-style route map at <http://localhost:8090>.

The compose stack does not include or modify the game server or its database. The map explorer reads a generated snapshot of `spz-races/data/tracks.lua`; rerun `tools/export_tracks.py` after adding or editing track definitions.

## Poll history migration

The migration is registered in `spz-core/server/migrations.lua`. The next server start creates the poll history tables; each subsequent poll saves its offered options, vote counts, participation, cop-chase tally, winner, and reroll status. Existing race history already comes from `race_sessions`, `race_results`, and `track_records`.

## Dashboard panels

- Race and entrant volume, average race length, DNF rate, and unique drivers
- Race volume over time, starter/finisher trend, and daily active drivers
- Popular tracks and class distribution
- Track records and best-lap trends
- Recent race history and result history
- Poll participation, vote breakdown, rerolls, traffic votes, and cop-chase votes
- Filters for time range, track, track type, and car class

The route explorer shows circuit/sprint checkpoint paths in the game world's local XY coordinates, matching the route previews used by the poll UI. It is an overhead route map rather than a real-world basemap.
