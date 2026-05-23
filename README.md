# movebank-rocker

A pinned R environment for working with [Movebank](https://www.movebank.org)
data — `rocker/geospatial` plus the canonical Movebank R clients
(`move`, `move2`) and movement-visualisation packages (`moveVis`, `sf`),
versions pinned to a known-good matrix.

Skip the GDAL / udunits / PROJ install dance: `docker pull` and the R
environment is ready to use.

```bash
docker run -p 8787:8787 \
    --add-host=host.docker.internal:host-gateway \
    -e PASSWORD=movebank \
    mcb77/movebank-rocker:latest
```

Open <http://localhost:8787> → log in as `rstudio` / `movebank` → you
have RStudio Server with everything pre-installed.

---

## What's in it

Base image: `rocker/geospatial:4.4.2` (R 4.4.2 + RStudio Server + the
full geospatial stack: GDAL, PROJ, GEOS, UDUNITS).

Added R packages:

| Package              | What for                                                |
|----------------------|---------------------------------------------------------|
| `move`               | The original Movebank R client (v1 / "classic")         |
| `move2`              | The modern Movebank R client (v2, simple-features based)|
| `moveVis`            | Animated trajectory visualisations                      |
| `rnaturalearth`      | Country / region polygons for base maps                 |
| `rnaturalearthdata`  | The data tables `rnaturalearth` reads                   |

`ggplot2`, `sf`, `dplyr`, etc. come from the rocker/geospatial base.

Versions are pinned indirectly via the rocker tag plus the Posit Public
Package Manager snapshot in effect at build time. To inspect what was
installed in a given image tag:

```bash
docker run --rm mcb77/movebank-rocker:<tag> \
    R -e "installed.packages()[c('move','move2','moveVis','sf'), 'Version']"
```

---

## Using it with `movebank-mirror-api`

This image's reason to exist: paired with
[`movebank-mirror-api`](https://github.com/mcb77/movebank-mirror-api),
your R workflows run offline against a local mirror of Movebank.

```bash
# On the host:
movebank-mirror-api -d /var/lib/movebank-mirror &

# In another shell (adjust the -v path to your local checkout of
# movebank-mirror-api):
docker run -p 8787:8787 \
    --add-host=host.docker.internal:host-gateway \
    -e PASSWORD=movebank \
    -v ~/devel/movebank-mirror-api/compatibility:/work:ro \
    mcb77/movebank-rocker:latest
```

The container's pre-baked `.Rprofile` already sets
`options(move2_movebank_api_url = "http://host.docker.internal:8080/...")`,
so `move2::movebank_download_study(...)` reads from the local mirror
without changes to your scripts.

For `move` v1 (which hardcodes the live URL inside the package), source
the URL shim from your mounted `/work` directory:

```r
source("/work/move-r/url_shim.R")
login <- movebankLogin(username = "ignored", password = "ignored")
override_url(login, "http://host.docker.internal:8080/movebank")
# now move::getMovebank*(...) reads from the local mirror
```

The shim, plus a `verify.R` regression-test script, ship in
`movebank-mirror-api/compatibility/move-r/`.

---

## Using it against the live Movebank API

You don't need `movebank-mirror-api`. The image is also a pinned R
environment for working against the live Movebank API:

```bash
docker run -p 8787:8787 \
    -e PASSWORD=movebank \
    -e MOVEBANK_MIRROR_API_URL=https://www.movebank.org/movebank \
    mcb77/movebank-rocker:latest
```

Or just `unset` the option inside your R session and call
`movebankLogin(...)` with real credentials.

---

## Verifying the install

Run the regression-test suite against a running `movebank-mirror-api`:

```bash
docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    -e MOVEBANK_MIRROR_API_URL=http://host.docker.internal:8080/movebank \
    -v ~/devel/movebank-mirror-api/compatibility:/work:ro \
    mcb77/movebank-rocker:latest \
    Rscript /work/move-r/verify.R
```

Should print `4/4 checks passed`. Repeat against
`/work/move2-r/verify.R` for the v2 client.

---

## Versioning

This image is versioned **independently** of `movebank-mirror-api`.
A CRAN update to `move2` warrants a new tag here without touching the
mirror-api. Conversely, a Spring Boot patch on the mirror-api side
doesn't require an image rebuild.

The image tag scheme is `vMAJOR.MINOR.PATCH`. The most recent tag is
also published as `latest`.

For long-running pipelines: **pin to a specific tag**, not `latest`.
The whole point of this image is reproducibility.

---

## Platform support

x86-64 only as of v0.1.0. Apple Silicon (M-series) users need
`--platform linux/amd64` and will run via emulation (slower; tolerable
for interactive use, not for batch). Multi-arch builds are on the
roadmap once the R spatial stack's ARM story stabilises.

---

## Building from source

```bash
git clone https://github.com/mcb77/movebank-rocker.git
cd movebank-rocker
docker build -t movebank-rocker:dev .
```

First build is ~10 minutes (R package install). Subsequent builds with
cached layers are seconds.

---

## Publishing a new release

See [`PUBLISHING.md`](PUBLISHING.md).

---

## Family of tools

`movebank-rocker` is one piece of an open-source Movebank toolchain.
See the siblings:

- [`movebank-api-client`](https://github.com/mcb77/movebank-api-client) —
  Java client for the Movebank REST API
- [`movebank-mirror`](https://github.com/mcb77/movebank-mirror) —
  sync Movebank studies to a local file/folder structure
- [`movebank-mirror-api`](https://github.com/mcb77/movebank-mirror-api) —
  a local replay server that re-serves the mirror through Movebank's
  REST API

---

## License

**MIT** for the recipe in this repo — Dockerfile, `.Rprofile`, GitHub
Actions workflow, and docs. See [`LICENSE`](LICENSE). Fork and adapt
freely.

The image built from this recipe is a different matter. It bundles R
itself (GPL-2.0), the `move` / `move2` / `moveVis` R packages
(GPL-3.0), and many transitive dependencies under various open-source
licenses. Anyone redistributing the **built image** is bound by those
licenses — effectively GPL-3.0 from the Movebank R clients. MIT here
covers the recipe, not the artifact you build with it.

This is a community tool, not an official Movebank product. Built
independently against the public Movebank API.
