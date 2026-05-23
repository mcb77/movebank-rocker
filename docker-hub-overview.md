# movebank-rocker

A pinned R environment for working with Movebank data. Skip the GDAL /
udunits / PROJ install dance — `docker pull` and the R environment is
ready to use.

## Quick start

    docker run -p 8787:8787 \
        --add-host=host.docker.internal:host-gateway \
        -e PASSWORD=movebank \
        mcb77/movebank-rocker:latest

Open <http://localhost:8787> and log in as `rstudio` / `movebank`.

## What's in it

Base: `rocker/geospatial:4.4.2` — R 4.4.2 + RStudio Server + the full
geospatial stack (GDAL, PROJ, GEOS, UDUNITS).

R packages added on top:

- `move` — original Movebank R client
- `move2` — modern Movebank R client (simple-features based)
- `moveVis` — animated trajectory visualisations
- `sf`, `rnaturalearth`, `rnaturalearthdata` — spatial / map basics

## Pairs with the rest of the Movebank toolchain

- [`movebank-api-client`](https://github.com/mcb77/movebank-api-client) — Java client for the Movebank REST API
- [`movebank-mirror`](https://github.com/mcb77/movebank-mirror) — sync studies to a local file/folder structure
- [`movebank-mirror-api`](https://github.com/mcb77/movebank-mirror-api) — local replay server for the mirror

Use those together with this image to run R analyses offline against a
local Movebank mirror — your `move`/`move2` scripts work unchanged.

## Source, docs, version matrix

→ <https://github.com/mcb77/movebank-rocker>

## License

MIT for the recipe. The image bundles GPL-licensed software (R itself,
the Movebank R clients) — see the GitHub repo's LICENSE notes for the
recipe-vs-image distinction.
