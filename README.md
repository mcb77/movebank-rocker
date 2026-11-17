# movebank-rocker

A pinned R environment for working with [Movebank](https://www.movebank.org)
data — `rocker/geospatial` plus the canonical Movebank R clients
(`move`, `move2`) and movement-visualisation packages (`moveVis`, `sf`),
every version pinned: base image by digest, CRAN packages by a dated
snapshot, `moveVis` by commit. The same tag gives you the same packages.

Skip the GDAL / udunits / PROJ install dance: `docker pull` and the R
environment is ready to use.

```bash
docker run -p 8787:8787 \
    -e PASSWORD=movebank \
    mcb77/movebank-rocker:latest
```

Open <http://localhost:8787> → log in as `rstudio` / `movebank` → you
have RStudio Server with everything pre-installed.

Without further settings, `move2` and `move` talk to movebank.org as usual
(see [Using it against the live Movebank API](#using-it-against-the-live-movebank-api)).
The `--add-host` / networking flags come in below, once you point the
container at a local `movebank-mirror-api`.

---

## What's in it

Base image: `rocker/geospatial:4.4.2` (R 4.4.2 + RStudio Server + the
full geospatial stack: GDAL, PROJ, GEOS, UDUNITS).

Added R packages (versions in `v0.2.0`):

| Package              | Version | What for                                                |
|----------------------|---------|---------------------------------------------------------|
| `move`               | 4.2.6   | The original Movebank R client (v1 / "classic")         |
| `move2`              | 0.4.4   | The modern Movebank R client (v2, simple-features based)|
| `moveVis`            | 1.0.1   | Animated trajectory visualisations                      |
| `rnaturalearth`      | 1.0.1   | Country / region polygons for base maps                 |
| `rnaturalearthdata`  |         | The data tables `rnaturalearth` reads                   |

`ggplot2` 3.5.1, `sf` 1.0-19, `terra` 1.8-29, `dplyr` etc. come from the
rocker/geospatial base.

### How the versions are pinned

| What | Pinned by | Where |
|---|---|---|
| R, RStudio Server, GDAL/PROJ/GEOS | `rocker/geospatial:4.4.2` **by digest** (a tag can be rebuilt under the same name) | `FROM` in the [`Dockerfile`](Dockerfile) |
| CRAN packages | the dated Posit Package Manager snapshot `2025-02-27` (binaries for Ubuntu noble) | `ARG CRAN_SNAPSHOT` |
| `moveVis` (no longer on CRAN) | GitHub commit `cf88cdc` (2025-08-22) | `ARG MOVEVIS_REF` |

The build checks the key versions (`ARG EXPECTED_VERSIONS`) and fails if
they differ, so a rebuild can't drift silently. The full list of installed
packages is in the image at `/usr/local/share/movebank-rocker-packages.csv`.

Packages you install yourself inside the container come from the same
snapshot, so they fit the rest. To cite the environment in a paper, give
the image tag, e.g. `mcb77/movebank-rocker:v0.2.0`.

To inspect what was installed in a given image tag:

```bash
docker run --rm mcb77/movebank-rocker:<tag> \
    R -e "installed.packages()[c('move','move2','moveVis','sf'), 'Version']"
```

---

## Using it with `movebank-mirror-api`

Paired with
[`movebank-mirror-api`](https://github.com/mcb77/movebank-mirror-api),
your R workflows run offline against a local mirror of Movebank.

How the container reaches the host's mirror server differs by platform. Start
the server on the host first (adjust the `-v` path to your checkout):

```bash
movebank-mirror-api -d /var/lib/movebank-mirror &
```

**Linux — host networking (server stays loopback-only, which is safer):**

```bash
docker run --network=host \
    -e PASSWORD=movebank \
    -e MOVEBANK_MIRROR_API_URL=http://localhost:8080/movebank \
    -v ~/devel/movebank-mirror-api/compatibility/compat:/work:ro \
    mcb77/movebank-rocker:latest
```

**macOS / Windows (Docker Desktop) — bridge; `host.docker.internal` reaches the host:**

```bash
docker run -p 8787:8787 \
    --add-host=host.docker.internal:host-gateway \
    -e PASSWORD=movebank \
    -v ~/devel/movebank-mirror-api/compatibility/compat:/work:ro \
    mcb77/movebank-rocker:latest
```

> On **Linux**, the bridge variant only works if the server is bound to all
> interfaces (`movebank-mirror-api -d … -b 0.0.0.0`) — the default `127.0.0.1`
> bind refuses the container's gateway-IP requests. That exposes the
> unauthenticated server on your LAN, so prefer host networking on Linux.

The container's pre-baked `.Rprofile` sets `move2_movebank_api_url` from
`MOVEBANK_MIRROR_API_URL`, so `move2::movebank_download_study(...)` reads from
the local mirror without changes to your scripts. Without that variable the
container leaves `move2` alone and it talks to movebank.org.

For `move` v1 (which hardcodes the live URL inside the package), source the URL
shim from your mounted `/work` directory and point it at the same URL the
container uses:

```r
source("/work/move-r/url_shim.R")
login <- movebankLogin(username = "ignored", password = "ignored")
# same URL the container was told about (localhost under host networking,
# host.docker.internal under the Docker Desktop bridge):
api <- Sys.getenv("MOVEBANK_MIRROR_API_URL")
override_url(login, api)
# now move::getMovebank*(...) reads from the local mirror
```

The shim, plus a `verify.R` regression-test script, ship in
`movebank-mirror-api/compatibility/compat/move-r/`.

---

## Using it against the live Movebank API

You don't need `movebank-mirror-api`. Without `MOVEBANK_MIRROR_API_URL`
the image is a plain pinned R environment, and `move2` / `move` talk to
movebank.org with your Movebank account:

```bash
docker run -p 8787:8787 -e PASSWORD=movebank mcb77/movebank-rocker:latest
```

`move2` normally keeps your password in the system keyring, which a
container doesn't have. Pass a handle instead; RStudio asks for the
password and nothing is stored:

```r
library(move2)
h <- movebank_handle("your-movebank-username")
study <- movebank_download_study(2911040, handle = h)
```

With `move`: `login <- movebankLogin(username = "your-movebank-username")`
asks for the password in the console (what you type is visible there).

---

## Under the hood: the `.Rprofile` customisations

To make "your existing R scripts just work against a local mirror"
land cleanly, the container's `.Rprofile` does two non-trivial things
once `move2` attaches. Worth knowing about, both so the behaviour
isn't surprising and so you can opt out cleanly.

### 1. The `move2_movebank_api_url` option is re-set after `move2` attaches

`.Rprofile` sets `options(move2_movebank_api_url = ...)` at session
start. But `move2`'s `.onLoad` hook **unconditionally resets that
option** to its built-in default (the live Movebank URL) when the
package loads — clobbering whatever we set. To win the race,
`.Rprofile` registers a hook on `packageEvent("move2", "attach")`
that re-sets the option after `.onLoad` and `.onAttach` have both
fired.

Symptom of this not working: `getOption("move2_movebank_api_url")`
shows the live URL after `library(move2)`, even though the container
is supposed to point at your local mirror.

### 2. `move2:::movebank_handle()` is rebound to skip the keyring lookup

`move2`'s `movebank_handle()` defaults to fetching credentials from
the system `keyring` R package, which isn't (and shouldn't be) in
this image. Against a local mirror that ignores credentials, that
lookup is pointless — but `movebank_download_study()` and friends
call `movebank_handle()` internally and prompt for keyring setup
when nothing is there.

So `.Rprofile` rebinds `movebank_handle` in `move2`'s namespace to
default `username` and `password` to `"ignored"` when none are
supplied, then forwards to the original implementation. The mirror
accepts these.

Symptom of this not working: `movebank_download_study(...)` prompts
"the package keyring is required to create a movebank handle —
would you like to install it?" instead of just running.

### The local-mirror guard

**Both customisations only apply when the configured URL points at a
local mirror** — specifically, the URL must start with
`http://host.docker.internal`, `http://localhost`, or
`http://127.0.0.1`.

If you re-point the container at the live API:

```bash
docker run -p 8787:8787 -e PASSWORD=movebank \
    -e MOVEBANK_MIRROR_API_URL=https://www.movebank.org/movebank \
    mcb77/movebank-rocker:latest
```

…the guard skips both rebindings. `move2` runs with its stock
behaviour: real keyring lookup, real `.onLoad` URL default. The
image remains a perfectly normal pinned R environment against the
real Movebank with real credentials — useful for validating a
local-mirror-derived analysis against the upstream as a sanity
check.

### Why monkey-patch?

The two customisations rebind functions in `move2`'s namespace
rather than asking `move2` to ship a no-keyring/no-default code
path. Same pattern as
[`url_shim.R`](https://github.com/mcb77/movebank-mirror-api/blob/master/compatibility/compat/move-r/url_shim.R)
for `move` v1, which works around the hardcoded live URL in
`move::getMovebank()`.

Both are pragmatic: the upstream packages were designed for the
single-server, real-credentials use case, and the local-mirror
scenario isn't a first-class citizen yet. The patches are small,
localised, and guarded by the local-URL check — the upstreams'
behaviour for their main audience is unchanged.

Trade-off: pinning to a specific `move2` version matters. If a
future `move2` renames `movebank_handle` or restructures its auth
dispatch, the rebinding silently no-ops (or errors confusingly).
The smoke-test in
[`PUBLISHING.md` §2.4](PUBLISHING.md) catches that — both the URL
option path and the `movebank_handle()` path are exercised on every
build, and a failure tells you the rebinding stopped working before
the image gets published.

The implementation lives in [`/.Rprofile`](.Rprofile) — ~30 lines,
worth a skim before extending the image.

---

## Verifying the install

Run the regression-test suite against a running `movebank-mirror-api`.

**Linux (host networking):**

```bash
docker run --rm --network=host \
    -e MOVEBANK_MIRROR_API_URL=http://localhost:8080/movebank \
    -v ~/devel/movebank-mirror-api/compatibility/compat:/work:ro \
    mcb77/movebank-rocker:latest \
    Rscript /work/move-r/verify.R
```

**macOS / Windows (Docker Desktop):**

```bash
docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    -e MOVEBANK_MIRROR_API_URL=http://host.docker.internal:8080/movebank \
    -v ~/devel/movebank-mirror-api/compatibility/compat:/work:ro \
    mcb77/movebank-rocker:latest \
    Rscript /work/move-r/verify.R
```

Should print `4/4 checks passed`. Repeat against
`/work/move2-r/verify.R` for the v2 client. (On Linux with the bridge variant,
start the server with `-b 0.0.0.0` — see the note above.)

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
