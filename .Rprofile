# Loaded automatically at the start of every R session in the container.
# Override at run time with `-e MOVEBANK_MIRROR_API_URL=...` on docker run,
# or by mounting a different .Rprofile over this one.
local({
    api <- Sys.getenv("MOVEBANK_MIRROR_API_URL",
                      unset = "http://host.docker.internal:8080/movebank")
    options(move2_movebank_api_url = paste0(api, "/service/direct-read"))
    # `move` v1 hardcodes the live URL inside getMovebank(); the URL
    # override has to be applied per-session by sourcing url_shim.R from a
    # mounted movebank-mirror-api/compatibility/move-r/ directory and
    # calling override_url(login, api). It can't safely live here because
    # move's namespace isn't guaranteed to be loaded at session start.
})
