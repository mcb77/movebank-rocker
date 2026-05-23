# Loaded automatically at the start of every R session in the container.
# Override at run time with `-e MOVEBANK_MIRROR_API_URL=...` on docker run,
# or by mounting a different .Rprofile over this one.
local({
    api <- Sys.getenv("MOVEBANK_MIRROR_API_URL",
                      unset = "http://host.docker.internal:8080/movebank")
    url <- paste0(api, "/service/direct-read")

    # Set the option now, in case move2 isn't loaded yet — and the .Rprofile
    # path is the obvious one to inspect with getOption(...) before any
    # library() call.
    options(move2_movebank_api_url = url)

    # ...and ALSO re-set it after move2 attaches. move2's .onLoad hook
    # unconditionally resets move2_movebank_api_url to the live URL,
    # clobbering whatever we set above. The packageEvent("attach") hook
    # fires after .onAttach, which is after .onLoad — so this runs last
    # and wins.
    setHook(packageEvent("move2", "attach"), function(...) {
        options(move2_movebank_api_url = url)

        # If the URL points at a local mirror, move2's credential lookup
        # is pointless — the mirror ignores credentials. Inject dummy
        # values into movebank_handle() so movebank_download_study() and
        # friends don't prompt for keyring setup. Only applied for
        # local-mirror URLs; live-API URLs still go through move2's
        # normal keyring-based auth.
        is_local <- grepl(
            "^http://(host\\.docker\\.internal|localhost|127\\.0\\.0\\.1)",
            url
        )
        if (is_local) {
            ns <- asNamespace("move2")
            original <- ns$movebank_handle
            wrapped <- function(username = NULL, password = NULL, ...) {
                if (is.null(username) && is.null(password)) {
                    username <- "ignored"
                    password <- "ignored"
                }
                original(username = username, password = password, ...)
            }
            unlockBinding("movebank_handle", ns)
            assign("movebank_handle", wrapped, envir = ns)
            lockBinding("movebank_handle", ns)
        }
    })

    # `move` v1 hardcodes the live URL inside getMovebank(); the URL
    # override has to be applied per-session by sourcing url_shim.R from a
    # mounted movebank-mirror-api/compatibility/move-r/ directory and
    # calling override_url(login, api). It can't safely live here because
    # move's namespace isn't guaranteed to be loaded at session start.
})
