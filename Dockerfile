# Everything that decides which versions end up in the image is pinned here.
# To move the matrix forward, change these values (see PUBLISHING.md §2.2),
# then update EXPECTED_VERSIONS from the build output.

# Base: R 4.4.2 + RStudio Server + GDAL/PROJ/GEOS/UDUNITS. Pinned by digest,
# because a rocker tag can be rebuilt under the same name.
FROM rocker/geospatial:4.4.2@sha256:7c86cef68a87fddff049acfa7877929d0d9ae6b133cfd1e57052549c268c6e1d

# CRAN packages come from this dated Posit Public Package Manager snapshot
# (binaries for Ubuntu noble). It is the snapshot rocker/geospatial:4.4.2
# already uses; stating it here makes it visible and changeable in one place.
ARG CRAN_SNAPSHOT=https://p3m.dev/cran/__linux__/noble/2025-02-27

# moveVis is no longer on CRAN; install it from GitHub at a fixed commit
# (2025-08-22, "added fill_na_values to align_move"), not from HEAD.
ARG MOVEVIS_REF=16EAGLE/moveVis@cf88cdcc0a44bd48c7f0bd35bc3f40f6d3f94283

# The build fails if the installed versions differ from these.
ARG EXPECTED_VERSIONS="move=4.2.6 move2=0.4.4 moveVis=1.0.1 sf=1.0-19 terra=1.8-29 rnaturalearth=1.0.1"

# pak installs binaries from P3M in parallel: ~5 min instead of ~25 from source.
RUN R -e "options(repos = c(CRAN = '${CRAN_SNAPSHOT}')); \
          install.packages('pak'); \
          pak::pkg_install(c('move', 'move2', '${MOVEVIS_REF}', \
                             'rnaturalearth', 'rnaturalearthdata'))"

# Fail the build if a key package has another version than expected, and
# write the full package list into the image.
RUN Rscript -e "exp <- strsplit(strsplit('${EXPECTED_VERSIONS}', ' ')[[1]], '='); \
          bad <- Filter(function(p) packageVersion(p[1]) != package_version(p[2]), exp); \
          for (p in bad) message('version mismatch: ', p[1], ' expected ', p[2], \
                                 ', got ', as.character(packageVersion(p[1]))); \
          if (length(bad)) quit(status = 1); \
          ip <- installed.packages(); \
          write.csv(ip[, c('Package', 'Version')], '/usr/local/share/movebank-rocker-packages.csv', \
                    row.names = FALSE)"

# Pre-configure the move2 URL override. .Rprofile is loaded at the start
# of every R session in the container.
COPY .Rprofile /home/rstudio/.Rprofile
RUN chown rstudio:rstudio /home/rstudio/.Rprofile

EXPOSE 8787
