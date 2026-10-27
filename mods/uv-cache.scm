;;; uv-cache.scm — one uv cache, $XDG_CACHE_HOME/uv on the host, shared by every
;;; container (and the host's own uv).  uv locks the cache, so concurrent use
;;; is safe.  $XDG_CACHE_HOME/uv must already exist on the host (gx-sb stops
;;; otherwise).
;;;
;;; The cache and the project are different mounts, so uv can't hardlink from
;;; one into the other's .venv; it would fall back to copying with a warning.
;;; Copy mode says so up front.

(add-env! "UV_CACHE_DIR" (host-share! (mk-path (xdg-cache-home) "uv")))
(add-env! "UV_LINK_MODE" "copy")
