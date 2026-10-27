;;; claude.scm — Claude Code, with settings and credentials shared with
;;; the host:
;;;   settings.json, keybindings.json  ->  $XDG_CONFIG_HOME/claude/
;;;   .credentials.json                ->  $XDG_DATA_HOME/claude/credentials.json
;;; Only those three files are shared, each at /host<host path>, not their
;;; directories, so all three must already exist on the host (gx-sb stops
;;; otherwise).  Each is bind-mounted on its own: it can be written in place
;;; from the container, but not deleted or replaced by renaming another file
;;; over it.
;;; credentials.json must not be accessible to group or others (mode
;;; xxx------, e.g. 600), or gx-sb stops.
;;; The files in .container/home/.claude are symlinks to those, remade before
;;; and after each run: a real file there (one left from before, or one Claude
;;; Code wrote in place of its symlink) is replaced without a backup.

(add-packages! "curl" "nss-certs")

;; Use Guix's ripgrep, not Claude's bundled one.
(add-env! "USE_BUILTIN_RIPGREP" "0")

;; Install Claude Code on first use (into ~/.local, i.e. .container/home/.local).
(add-setup! "
if [ ! -x \"$HOME/.opencode/bin/opencode\" ]; then
  echo 'gx-sb: installing opencode...' >&2
  curl -fsSL https://opencode.ai/v2/install | bash
fi")
