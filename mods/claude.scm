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

(add-packages! "curl" "ripgrep" "grep" "sed")

;; Use Guix's ripgrep, not Claude's bundled one.
(add-env! "USE_BUILTIN_RIPGREP" "0")

;; Install Claude Code on first use (into ~/.local, i.e. .container/home/.local).
(add-setup! "
if [ ! -x \"$HOME/.local/bin/claude\" ]; then
  echo 'gx-sb: installing Claude Code...' >&2
  curl -fsSL https://claude.ai/install.sh | bash
fi")

(let ((config (mk-path (xdg-config-home) "claude"))
      (data   (mk-path (xdg-data-home) "claude")))
  (let ((path "/host/settings.json"))
      (add-share! (mk-path config "settings.json") path)
      (add-link! ".claude/settings.json" path))
  (let ((path "/host/keybindigs.json"))
      (add-share! (mk-path config "keybindings.json") path)
      (add-link! ".claude/keybindings.json" path))
  (let ((creds (mk-path data "credentials.json"))
        (path "/host/credentials.json"))
    (add-share! (mk-path data "credentials.json") path)
    (add-link! ".claude/.credentials.json" path)
    (unless (zero? (logand (stat:perms (stat creds)) #o077))
      (die "~a is accessible to group or others; run: chmod go= ~a"
           creds (sh-quote creds)))))
