# Publishing workflow

`movebank-rocker` ships a single artifact:

| Artifact                              | Channel       |
|---------------------------------------|---------------|
| `mcb77/movebank-rocker:<tag>` image   | Docker Hub    |

For the family-wide story (sibling repos, Maven Central publication of
the Java artifacts, the relationship to `movebank-mirror-api`), see
[`README.md`](README.md). This document covers the Docker-Hub-specific
release workflow.

The family's *other* publication target is Maven Central; if you've
followed the
[`movebank-api-client/PUBLISHING.md`](https://github.com/mcb77/movebank-api-client/blob/master/PUBLISHING.md)
or
[`movebank-mirror/PUBLISHING.md`](https://github.com/mcb77/movebank-mirror/blob/master/PUBLISHING.md)
workflow, the *shape* of this document will be familiar — same Part 1
"one-time setup" + Part 2 "per-release recipe" pattern. The mechanics
underneath are entirely different (no PGP signing, no namespace
verification, no state-machine watch), but the discipline is the same.

---

## Part 1. One-time setup

### 1.1 Docker Hub account

Create an account at <https://hub.docker.com> if you don't have one
yet. The username matters: the image's full coordinate is
`<username>/<repo>:<tag>`, so for `mcb77/movebank-rocker` the Docker
Hub username must be `mcb77`. Names are unique globally; pick before
you publish.

Public repos are free. No paid tier needed for this artifact.

### 1.2 Create the Docker Hub repository

After the account exists:

1. <https://hub.docker.com/repository/create>
2. Namespace: `mcb77`, name: `movebank-rocker`, visibility: **Public**.
3. Set a short description (carries through to search results). Match
   the GitHub repo description verbatim for consistency:
   *"Pinned R environment for working with Movebank — rocker/geospatial
   + move/move2/moveVis/sf, ready to use."*
4. Leave "Build settings" empty. We're pushing from GitHub Actions,
   not using Docker Hub's auto-builders.

### 1.3 Generate a Docker Hub access token

Don't use your account password from CI. Generate a scoped token:

1. <https://hub.docker.com/settings/security>
2. *New Access Token*. Description: "GitHub Actions: movebank-rocker".
   Permissions: **Read, Write, Delete** (we need write for push;
   delete is rarely used but easier to grant once than to revisit).
3. Copy the token immediately — Docker Hub shows it once.

### 1.4 Wire the secrets into the GitHub repo

The workflow at `.github/workflows/build.yml` references two secrets.
Set both at <https://github.com/mcb77/movebank-rocker/settings/secrets/actions>:

| Secret                | Value                                  |
|-----------------------|----------------------------------------|
| `DOCKERHUB_USERNAME`  | your Docker Hub username (`mcb77`)     |
| `DOCKERHUB_TOKEN`     | the token generated in §1.3            |

Without these, the workflow will fail at the `docker/login-action`
step with `Error: Username and password required`.

### 1.5 Sync the Docker Hub long description

Docker Hub's repo page renders a long description below the short one.
It's a separate field from the short description in §1.2 and *isn't*
automatically synced from the README. The canonical text lives in this
repo at [`docker-hub-overview.md`](docker-hub-overview.md) — keeping
it as a versioned file means git tracks every change.

Two ways to push it to Docker Hub:

- **Copy by hand.** Paste `docker-hub-overview.md` into the "Overview"
  tab on the Docker Hub repo page after any meaningful change to the
  file. Low ceremony, the right call for the first few releases.
- **Wire in `peter-evans/dockerhub-description@v4`** in the Actions
  workflow once the file stabilises. Uses the same `DOCKERHUB_TOKEN`
  secret and points its `readme-filepath` input at
  `./docker-hub-overview.md`. Then every push to `master` updates
  Docker Hub automatically. Not worth the noise until the file stops
  churning weekly.

---

## Part 2. Cutting a release

### 2.1 Decide what's changing

Three reasons to cut a new tag, in order of how common they should be:

1. **Package bump in one of the pinned R packages.** `move` and
   `move2` updates land on CRAN regularly. `moveVis` was archived from
   CRAN in late 2024 — we install it from `16EAGLE/moveVis` (GitHub
   HEAD) instead, and a new commit there is its own reason to rebuild.
   We follow either source with a fresh image so the pinned matrix
   advances.
2. **Base image bump.** `rocker/geospatial` releases follow the R
   release cadence (roughly twice a year). When R moves from 4.4.x to
   4.5.x, bump the `FROM` line.
3. **Dockerfile change** — adding a package, changing an entrypoint,
   fixing a permission bug. Less common.

Reasons that are *not* releases of `movebank-rocker`:
- A `movebank-mirror-api` patch release. The two repos are
  intentionally decoupled — see the
  [README's versioning note](README.md#versioning).
- A `movebank-mirror` patch release. Same reason.

### 2.2 Update the Dockerfile if needed

For a CRAN-bump-only release, no source changes are needed: `pak`
re-resolves the latest binaries from P3M at build time. Just tag.

For a base-image bump, edit the first line:

```dockerfile
FROM rocker/geospatial:4.5.0
```

For a pinned-package addition, extend the `pak::pkg_install(c(...))`
call.

### 2.3 Build locally first

Always smoke-test before tagging. Builds take ~5 minutes once the
`rocker/geospatial:4.4.2` base is cached locally (the R package install
layer is ~2 min; the rest is COPY + chown). Without the base cached,
add ~5 min for the initial ~4 GB pull. Subsequent builds with the
package-install layer cached: ~10 seconds.

```bash
docker build -t movebank-rocker:dev .
```

If `pak::pkg_install(...)` fails, the error usually surfaces a missing
system library that `rocker/geospatial` doesn't pre-install. Fix by
adding the system dep with `apt-get install` ahead of the R install
step.

### 2.4 Run the regression suite

Build is "did it compile"; regression is "does it actually work
against a real mirror." Start `movebank-mirror-api` on the host
(against a populated mirror) and run:

```bash
docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    -e MOVEBANK_MIRROR_API_URL=http://host.docker.internal:8080/movebank \
    -v /path/to/movebank-mirror-api/compatibility:/work:ro \
    movebank-rocker:dev \
    Rscript /work/move-r/verify.R
```

Expect `4/4 checks passed`. Repeat with `/work/move2-r/verify.R`.
**If either fails, do not tag** — the regression suite is the gate.

### 2.5 Commit and tag

```bash
git add Dockerfile .Rprofile           # whatever changed
git commit -m "Bump rocker base to 4.5.0"
git tag -a v0.2.0 -m "v0.2.0 — R 4.5.0 base"
git push origin master --tags
```

Tag scheme: `vMAJOR.MINOR.PATCH`. The Actions workflow triggers on any
tag matching `v*` and publishes to Docker Hub as
`mcb77/movebank-rocker:v0.2.0` *and* `mcb77/movebank-rocker:latest`.

### 2.6 Watch the workflow

<https://github.com/mcb77/movebank-rocker/actions>

The build job runs ~15–25 minutes from a cold CI cache:

```
checkout                                   ~5s
docker/login-action                        ~3s
docker/setup-buildx-action                 ~10s
docker/build-push-action  (build)          ~5–10 min  (incl. ~4 GB base pull)
docker/build-push-action  (push)           ~10–15 min (~7 GB upload)
```

The 7 GB image is on the high side because `moveVis`'s `av` /
ffmpeg dependencies inflate it from the ~4.5 GB a moveVis-less
image would be. The first publish is slow; subsequent publishes
that change only the package layer push a single ~500 MB layer.

If the workflow fails at the *login* step, recheck §1.4 — usually a
typo'd secret name or a token that expired.

If it fails at *build*, the issue is the Dockerfile — reproduce
locally with `docker build`.

If it fails at *push*, check Docker Hub's status page. Docker Hub
outages are rare but real; rerun the workflow once Docker Hub is
healthy.

### 2.7 Verify on Docker Hub

Once green:

```bash
docker pull mcb77/movebank-rocker:v0.2.0
docker image inspect mcb77/movebank-rocker:v0.2.0 | head -20
```

Pull works → the image exists on Docker Hub. Inspect should show the
tag, layers, and size (~7 GB).

For the strictest "did it actually work" check, pull on a *different*
machine from the one that built it and rerun the regression suite.
That catches "I had the package cached locally" mistakes.

### 2.8 (Optional) create a GitHub Release

The Docker Hub publish *is* the release, but a GitHub Release entry
gives you a human-readable changelog and a permanent landing page:

```bash
gh release create v0.2.0 \
    --title "v0.2.0" \
    --notes "$(cat <<'EOF'
Pinned R environment for Movebank work.

- Base: rocker/geospatial:4.5.0 (R 4.5.0)
- move 4.2.x, move2 0.4.x, moveVis 0.10.x

Pull:
  docker pull mcb77/movebank-rocker:v0.2.0
EOF
)"
```

The version-specific R package versions can be cribbed from
`docker run --rm mcb77/movebank-rocker:v0.2.0 R -e "installed.packages()[c('move','move2','moveVis','sf'), 'Version']"`.

---

## Part 2.alt. Manual publishing (no GitHub Actions)

Use this path when:

- **Cutting v0.1.0.** You've validated the image locally; uploading
  the bits you tested is more trustworthy than asking a fresh CI
  machine to rebuild and hoping the output is identical. Skip Actions
  for the first release.
- **An urgent patch.** Docker Hub outage, Actions failing, you need
  the image up *now*. Manual is the fast path.
- **You want to publish a specific local build** — e.g. from a beefy
  workstation whose layers are already cached, instead of waiting for
  a cold CI build.

Once `v0.1.0` is up and you trust the Actions setup end-to-end, prefer
the tag-driven Actions flow (Part 2) for the discipline.

### 2.alt.1 Prerequisites

- Docker Hub account + access token from §1.1–§1.3.
- A local image built and tested. Run the regression suite from §2.4
  before pushing — don't publish bits you haven't verified.

### 2.alt.2 Authenticate locally

```bash
docker login
# username: <docker-hub-username>
# password: <paste the access token from §1.3>
```

Credentials get cached in `~/.docker/config.json`. One-time per
machine.

### 2.alt.3 Tag and push

```bash
# Three tag pointers to the same image SHA — no rebuild, just labels.
docker tag movebank-rocker:dev mcb77/movebank-rocker:v<X.Y.Z>
docker tag movebank-rocker:dev mcb77/movebank-rocker:latest

# Push the version tag first (uploads the actual ~7 GB).
docker push mcb77/movebank-rocker:v<X.Y.Z>

# Push :latest second — sub-second, same layers, just a new tag.
docker push mcb77/movebank-rocker:latest
```

Upload time on the first push: ~10–15 min on a typical home
connection. Subsequent pushes that change only the package-install
layer move just that one ~500 MB layer; the base layers Docker Hub
already has.

### 2.alt.4 Validate the published image

Same as §2.7 but force a fresh pull first to make sure you're testing
what's actually on Docker Hub, not what's still in your local cache:

```bash
docker rmi mcb77/movebank-rocker:v<X.Y.Z> \
           mcb77/movebank-rocker:latest \
           movebank-rocker:dev
docker pull mcb77/movebank-rocker:v<X.Y.Z>
docker run --rm \
    --add-host=host.docker.internal:host-gateway \
    -e MOVEBANK_MIRROR_API_URL=http://host.docker.internal:8080/movebank \
    -v ~/devel/firetail/movebank-mirror-api/compatibility:/work:ro \
    -w /work/move-r \
    mcb77/movebank-rocker:v<X.Y.Z> \
    Rscript verify.R
```

`4/4 checks passed` → published artifact is good. The whole point of
the `docker rmi` first is to catch "I had it cached locally, the
upload was actually broken" type mistakes.

### 2.alt.5 Don't forget the git tag

The manual push doesn't touch git. After verifying the image is good,
also tag the source so future-you can find the commit that produced
each published version:

```bash
git tag -a v<X.Y.Z> -m "v<X.Y.Z>"
git push origin v<X.Y.Z>
```

**Skip this step and the published image becomes un-rebuildable** —
no commit-history record of which source produced it. The Actions
flow couples push to tag automatically; on the manual path you have
to hold yourself to the same discipline.

### When manual goes wrong: just rerun

If `docker push` dies mid-upload (flaky connection, Docker Hub
hiccup), rerun the same `docker push` command. Docker resumes from
the layer that wasn't fully uploaded — already-uploaded layers are
skipped. No special recovery needed.

If push fails with a permissions error, you're either not logged in
(`docker login` again) or the token in §1.3 didn't have write scope
(regenerate it).

---

## Part 3. Troubleshooting

### `401 Unauthorized` from Docker Hub during push

Token's wrong, expired, or scoped incorrectly. Regenerate at §1.3 with
**Read + Write** at minimum. Update the GitHub secret. Re-trigger the
workflow via *Actions → build-and-push → Re-run all jobs*.

### `pak::pkg_install` fails with a missing system library

The R package needs a system dep that `rocker/geospatial` doesn't
pre-install. Add it via apt before the R install step:

```dockerfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libavfilter-dev libavformat-dev \
    && rm -rf /var/lib/apt/lists/*
```

(Common culprits: `libavfilter-dev` for `av` / `moveVis`,
`libmagick++-dev` for `magick`, `libpoppler-cpp-dev` for `pdftools`.)

### `moveVis` can't be resolved by `pak`

`moveVis` was archived from CRAN in late 2024. `pak` won't find it
through any CRAN-flavoured source (including P3M binaries). The
Dockerfile pins it to its GitHub source as `16EAGLE/moveVis`. If a
future `pak` resolution starts failing on this line, check:

- The repo at <https://github.com/16EAGLE/moveVis> still exists and the
  default branch still builds.
- The maintainer hasn't renamed the repo or moved orgs.
- `moveVis` has been restored to CRAN (in which case revert the
  Dockerfile to plain `'moveVis'` and drop the GitHub-source friction).

### Image is too large

~7 GB is normal for this image. The `rocker/geospatial` base alone is
~4 GB; `moveVis`'s `av` / ffmpeg dependencies add ~2.5 GB more.
Not much room to shrink without giving up packages or moving to a
smaller base (which would defeat the purpose).

If size becomes a real problem, options in increasing order of
disruption:

1. Drop `moveVis` (and its transitive `av` video dep) — gets back to
   ~4.5 GB and excludes only the animation use case.
2. Switch the base from `rocker/geospatial` to `rocker/r-ver` and
   install the spatial stack ourselves — saves ~1 GB but adds a long
   apt step and breaks the "standard rocker workflow" framing.
3. Multi-stage build — install, then copy a subset into a slimmer
   final image. Fiddly with R; rarely worth it.

### ARM (Apple Silicon) users want a native build

Roadmap, not v0.1.0. Multi-arch via `docker/setup-qemu-action` +
`docker/build-push-action`'s `platforms: linux/amd64,linux/arm64`.
Doubles CI time and some R spatial packages don't build cleanly on
ARM emulation. Revisit when the R-spatial-on-ARM story stabilises.

### Container can't reach the host

The container talks to the host's `movebank-mirror-api` over network.
Two ways that work, depending on platform:

- **Linux:** `--network host` (simplest) *or* `--add-host
  host.docker.internal:host-gateway` (matches Mac/Windows).
- **Mac / Windows:** Docker Desktop auto-resolves
  `host.docker.internal` — no flag needed.

The image's default `MOVEBANK_MIRROR_API_URL` points at
`host.docker.internal`, so the cross-platform invocation is:

```bash
docker run --add-host=host.docker.internal:host-gateway ...
```

…on Linux, and the same command without `--add-host` on Mac/Windows.
Document this in any post / screencast.

### Docker Hub pull rate limit

Anonymous pulls are limited to ~100 per 6 hours per IP; authenticated
free-tier accounts ~200. For a course or workshop with many concurrent
students, this can bite.

Options:

- Have students `docker login` first — bumps the limit and is easy.
- Mirror the image to GitHub Container Registry: `ghcr.io` has no
  pull-rate limits for public images. One additional `docker/push-action`
  step in the workflow, one extra secret (`GHCR_TOKEN` — actually the
  built-in `GITHUB_TOKEN` works). Worth adding once a real workshop
  uses the image.

---

## Part 4. Per-release checklist

The checklist assumes the **Actions-driven** flow (Part 2). For the
manual path (Part 2.alt — recommended for v0.1.0), replace the
"git tag → workflow green" step with "docker tag + docker push +
git tag separately"; everything else is the same.

```
[ ] decided what's changing: package bump / base bump / Dockerfile change
[ ] Dockerfile edited (if needed) and committed locally
[ ] docker build -t movebank-rocker:dev . — success
[ ] regression suite passes:
      [ ] move-r/verify.R    → 4/4
      [ ] move2-r/verify.R   → 4/4

  -- Actions-driven path (Part 2) --
[ ] git tag -a v<X.Y.Z> -m '…' && git push --tags
[ ] Actions workflow green at github.com/mcb77/movebank-rocker/actions

  -- OR: manual path (Part 2.alt) --
[ ] docker login (if not cached)
[ ] docker tag movebank-rocker:dev mcb77/movebank-rocker:v<X.Y.Z>
[ ] docker tag movebank-rocker:dev mcb77/movebank-rocker:latest
[ ] docker push mcb77/movebank-rocker:v<X.Y.Z>     (~10–15 min)
[ ] docker push mcb77/movebank-rocker:latest       (sub-second)
[ ] git tag -a v<X.Y.Z> -m '…' && git push --tags  (don't forget!)

  -- both paths from here --
[ ] docker rmi + docker pull mcb77/movebank-rocker:v<X.Y.Z> (force fresh)
[ ] regression suite passes against pulled image
[ ] (optional) gh release create v<X.Y.Z> --title '…' --notes '…'
[ ] (optional) update Docker Hub long description if README changed
```
