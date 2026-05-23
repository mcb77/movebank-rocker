FROM rocker/geospatial:4.4.2

# Movebank R clients + viz packages. Use pak for parallel binary
# installs from Posit's package manager (P3M) — keeps the package
# install step to ~5 min instead of ~25 min from source.
RUN R -e "install.packages('pak'); \
          pak::pkg_install(c('move', 'move2', \
                             '16EAGLE/moveVis', \
                             'rnaturalearth', 'rnaturalearthdata'))"

# Pre-configure the move2 URL override. .Rprofile is loaded at the start
# of every R session in the container.
COPY .Rprofile /home/rstudio/.Rprofile
RUN chown rstudio:rstudio /home/rstudio/.Rprofile

EXPOSE 8787
