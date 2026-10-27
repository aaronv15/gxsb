#!/usr/bin/env -S guix repl --
!#
;;; vim:ft=scheme
;;; gx-sb — run a project inside a Guix container sandbox.
;;;
;;;   gx-sb [cmd [args ...]]
;;;
;;; Run it from a project root containing .container/gx-sb.scm, e.g.
;;;
;;;   ((packages ("git" "python" "uv"))
;;;    (mods ("nice-zsh" "uv-cache"))
;;;    (links (("/home/user/whatever" . ,(mk-path host-mount-root "foo")))))
;;;
;;; The file is read as a quasiquoted list of (KEY VALUE) clauses, so `,EXPR'
;;; evaluates EXPR with everything defined here in scope.  Keys:
;;;
;;;   packages     pacakges to add to container
;;;   mods         list of mod names (loaded in order)
;;;   links        list of (LINK . TARGET): LINK, a container path (relative
;;;                paths are under the container home), becomes a symlink to
;;;                TARGET; see `add-link!'
;;;   env          list of (NAME . VALUE) set inside the container
;;;   shares       list of (HOST-PATH . CONTAINER-PATH) shared read-write
;;;   exports      list of (HOST-PATH . CONTAINER-PATH) shared read-only
;;;   host-shares  list of host paths, each shared read-write at /host<path>
;;;   host-exports list of host paths, each shared read-only at /host<path>
;;;   setup        list of shell snippets run before the command
;;;   teardown     list of shell snippets run after it
;;;   shell-flags  list of extra `guix shell' flags
;;;   shell        interactive shell, e.g. "zsh" (see `shell' below)
;;;   command      default command; the shell when not given
;;;   user         user name inside the container
;;;   project-dir  where the project appears inside the container
;;;
;;; Every host path given to shares, exports, host-shares and host-exports
;;; (and to the matching API calls) must already exist: gx-sb stops with an
;;; error rather than creating it.
;;;
;;; A mod NAME is the file NAME.scm in .container/mods/ or, failing that,
;;; $XDG_CONFIG_HOME/gx-sb/mods/.  Mods are plain Guile evaluated on the host
;;; in this module: they `set!' the settings below and call the API.
;;;
;;; gx-sb maintains in .container/: .gitignore, manifest.scm (generated each
;;; run -- don't edit) and home/ (the container user's home).

(use-modules (ice-9 match)
             (srfi srfi-1))

;;; ---- Helpers --------------------------------------------------------------

(define (mk-path root . segments)
  (string-join (cons (string-trim-right root #\/)
                     (map (lambda (s)
                            (string-trim-both s #\/)) segments)) "/"))

(define (mkdir-p dir)
  (unless (file-exists? dir)
    (mkdir-p (dirname dir))
    (mkdir dir)))

(define (die fmt . args)
  (apply format
         (current-error-port)
         (string-append "gx-sb: " fmt "~%") args)
  (exit 1))

(define (get-host-env name default)
  "The host's environment variable NAME.  When it is unset or empty: DEFAULT
if that is a string, the result of calling DEFAULT if it is a procedure
(so it is only computed when needed), or, if DEFAULT is #f, gx-sb stops with
an error."
  (let ((v (getenv name)))
    (cond ((and v
                (not (string-null? v))) v)
          ((procedure? default) (default))
          (default default)
          (else (die "host environment variable ~a is not set" name)))))

(define (host-home)
  (get-host-env "HOME" #f))
(define (xdg-config-home)
  (get-host-env "XDG_CONFIG_HOME"
                (lambda () (mk-path (host-home) ".config"))))
(define (xdg-data-home)
  (get-host-env "XDG_DATA_HOME"
                (lambda () (mk-path (host-home) ".local/share"))))
(define (xdg-cache-home)
  (get-host-env "XDG_CACHE_HOME"
                (lambda () (mk-path (host-home) ".cache"))))

(define (sh-quote s)
  "S quoted for the shell."
  (string-append "'"
                 (string-join (string-split s #\') "'\\''") "'"))

;;; ---- Settings (config and mods may change these) --------------------------

;; User name inside the container; its home is /home/<user>, backed by
;; .container/home.
(define container-user
  "user")

;; Where the project directory appears inside the container.  Must not be
;; under /home/<user>: that is a separate mount, and a mount nested inside it
;; can end up hidden.
(define container-project-dir
  "/project")

;; Where host paths shared with `host-share!' or `host-export!' appear:
;; /host/<host path>.
(define host-mount-root
  "/host")

;; The interactive shell: the default command and $SHELL inside the
;; container.  It is also added as a package, so it must be a package name
;; that installs bin/<shell> (zsh, bash, fish, ...).  The bootstrap itself
;; always runs under bash.
(define shell "zsh")

;; Command when gx-sb gets no arguments; #f means `shell'.
(define default-command #f)

;; Written to ~/.<shell>rc in the container home if that file doesn't exist.
(define shellrc-contents "")

;;; ---- Paths ----------------------------------------------------------------

(define project-dir
  (getcwd))
(define container-dir
  (mk-path project-dir ".container"))
(define config-file
  (mk-path container-dir "gx-sb.scm"))
(define home-dir
  (mk-path container-dir "home"))
(define manifest-file
  (mk-path container-dir "manifest.scm"))

(define mod-dirs
  (list (mk-path container-dir "mods")
        (mk-path (xdg-config-home) "gx-sb" "mods")))

(define (container-home)
  (mk-path "/home" container-user))

;;; ---- API for config and mods ----------------------------------------------

;; What every container needs: the bootstrap uses bash and coreutils.  The
;; shell is added after the config is read, so a config or mod can change it.
(define packages
  '("bash" "diffutils" "coreutils" "ncurses" "foot"))
(define env-vars
  '(("LANG" . "C.UTF-8") ("TERM" . "foot"))) ; (name . value)
(define shares
  '())                                  ; (host-path . container-path), read-write
(define exports
  '())                                  ; (host-path . container-path), read-only
(define shell-flags
  '())                                  ; extra `guix shell' flags
(define links
  '())                                  ; (link . target), container paths
(define setup-snippets
  '())
(define teardown-snippets
  '())                                  ; shell, run in the container after the command

(define (add-packages! . specs)
  (set! packages
        (append packages specs)))

(define (add-env! name value)
  "Set NAME to VALUE inside the container (replacing an earlier `add-env!')."
  (set! env-vars
        (append (alist-delete name env-vars)
                `((,name . ,value)))))

(define (check-host-path host-path)
  (unless (file-exists? host-path)
    (die "host path ~a does not exist" host-path)))

(define (add-share! host-path container-path)
  "Share HOST-PATH read-write at CONTAINER-PATH.  HOST-PATH must exist: if it
doesn't, gx-sb stops with an error."
  (check-host-path host-path)
  (set! shares
        (append shares
                `((,host-path . ,container-path)))))

(define (add-export! host-path container-path)
  "Share HOST-PATH read-only at CONTAINER-PATH.  HOST-PATH must exist: if it
doesn't, gx-sb stops with an error."
  (check-host-path host-path)
  (set! exports
        (append exports
                `((,host-path . ,container-path)))))

(define (host-share! host-path)
  "Share HOST-PATH read-write at /host<HOST-PATH> and return that container
path.  HOST-PATH must exist: if it doesn't, gx-sb stops with an error."
  (let ((container-path (mk-path host-mount-root host-path)))
    (add-share! host-path container-path)
    container-path))

(define (host-export! host-path)
  "Share HOST-PATH read-only at /host<HOST-PATH> and return that container
path.  HOST-PATH must exist: if it doesn't, gx-sb stops with an error."
  (let ((container-path (mk-path host-mount-root host-path)))
    (add-export! host-path container-path)
    container-path))

(define (add-shell-flags! . flags)
  (set! shell-flags
        (append shell-flags flags)))

(define (add-link! link target)
  "Make LINK a symlink to TARGET, both container paths (a relative LINK is
under the container home; TARGET is typically under a `host-share!').  The
link is made with `ln -sfn' before and after the command runs, creating LINK's
directory if needed. If there is a file at LINK that is newer than TARGET,
the diff of the two files is printed and the user is asked which one to keep"
  (set! links
        (append links
                `((,link . ,target)))))

(define (add-setup! . snippets)
  (set! setup-snippets
        (append snippets setup-snippets)))

(define (add-teardown! snippet)
  (set! teardown-snippets
        (append teardown-snippets
                (list snippet))))

(define (load-mod name)
  "Load the mod NAME from the first of `mod-dirs' that has NAME.scm."
  (let ((file (find file-exists?
                    (map (lambda (dir)
                           (mk-path dir
                                    (string-append name ".scm"))) mod-dirs))))
    (unless file
      (die "mod ~s not found in ~a" name
           (string-join mod-dirs ", ")))
    (catch #t
           (lambda ()
             (primitive-load file))
           (lambda (key . args)
             ;; `die' exits by throwing 'quit: let it through.
             (if (eq? key 'quit)
                 (apply throw key args)
                 (die "error in mod ~a: ~s ~s" file key args))))))

;;; ---- Read the project config ----------------------------------------------

(define (strings? x)
  (and (list? x)
       (every string? x)))
(define (pairs? x)
  (and (list? x)
       (every pair? x)))

(define (apply-clause clause)
  (define (check ok? what value)
    (unless (ok? value)
      (die "~a: ~s should be ~a, got ~s" config-file
           (car clause) what value)))
  (match clause
    (('packages specs)
     (check strings? "a list of strings" specs)
     (apply add-packages! specs))
    (('mods names)
     (check strings? "a list of strings" names)
     (for-each load-mod names))
    (('links ls)
     (check pairs? "a list of (link . target)" ls)
     (for-each (match-lambda
                 ((l . t) (add-link! l t))) ls))
    (('env vars)
     (check pairs? "a list of (name . value)" vars)
     (for-each (match-lambda
                 ((k . v) (add-env! k v))) vars))
    (('shares ss)
     (check pairs? "a list of (host . container)" ss)
     (for-each (match-lambda
                 ((h . c) (add-share! h c))) ss))
    (('exports es)
     (check pairs? "a list of (host . container)" es)
     (for-each (match-lambda
                 ((h . c) (add-export! h c))) es))
    (('host-shares paths)
     (check strings? "a list of strings" paths)
     (for-each host-share! paths))
    (('host-exports paths)
     (check strings? "a list of strings" paths)
     (for-each host-export! paths))
    (('setup snippets)
     (check strings? "a list of strings" snippets)
     (for-each add-setup! snippets))
    (('teardown snippets)
     (check strings? "a list of strings" snippets)
     (for-each add-teardown! snippets))
    (('shell-flags flags)
     (check strings? "a list of strings" flags)
     (apply add-shell-flags! flags))
    (('shell name)
     (check string? "a string" name)
     (set! shell name))
    (('command cmd)
     (check strings? "a list of strings" cmd)
     (set! default-command cmd))
    (('user name)
     (check string? "a string" name)
     (set! container-user name))
    (('project-dir dir)
     (check string? "a string" dir)
     (set! container-project-dir dir))
    (_ (die "~a: unknown clause ~s" config-file clause))))

(unless (file-exists? config-file)
  (die "no ~a; run me from a project root that has one" config-file))

(mkdir-p home-dir)

(let ((config (catch #t
                     (lambda ()
                       (let ((datum (call-with-input-file config-file
                                      read)))
                         (if (eof-object? datum)
                             '()
                             (eval (list 'quasiquote datum)
                                   (current-module)))))
                     (lambda (key . args)
                       ;; `die' exits by throwing 'quit: let it through.
                       (if (eq? key 'quit)
                           (apply throw key args)
                           (die "error reading ~a: ~s ~s" config-file key
                                args))))))
  (unless (list? config)
    (die "~a should hold a list of (KEY VALUE) clauses" config-file))
  (for-each apply-clause config))

;;; ---- Settings derived from the shell (after config and mods) --------------

(add-packages! shell)

(unless default-command
  (set! default-command (list shell)))

;; An existing rc file stops e.g. zsh's new-user wizard from prompting on
;; start.
(let ((shellrc (mk-path home-dir (string-append "." shell "rc"))))
  (unless (file-exists? shellrc)
    (with-output-to-file shellrc
      (lambda ()
        (display shellrc-contents)))))

;;; ---- Generated files ------------------------------------------------------

;; Keep .container/ (including credentials) out of git without touching the
;; project's own .gitignore -- except the config and project mods.
(with-output-to-file (mk-path container-dir ".gitignore")
  (lambda ()
    (display "/*\n!/.gitignore\n!/gx-sb.scm\n!/mods/\n")))

(with-output-to-file manifest-file
  (lambda ()
    (display ";; Generated by gx-sb from .container/gx-sb.scm -- don't edit.
")
    (write `(specifications->manifest ',(delete-duplicates packages)))
    (newline)))

;;; ---- Bootstrap (runs inside the container, under bash) --------------------

(define link-function
"
link_file() {
  local link=$1 target=$2 ans
  mkdir -p \"$(dirname \"$link\")\"
  if [ -d \"$link\" ] && [ ! -L \"$link\" ]; then
    echo \"gx-sb: $link is a directory; not linking it to $target\" >&2
    return 0
  fi
  if [ -f \"$link\" ] && [ ! -L \"$link\" ] && [ \"$link\" -nt \"$target\" ]; then
    if [ ! -t 0 ]; then
      echo \"gx-sb: $link is newer than $target and there is no terminal to ask; left as is\" >&2
      return 0
    fi
    diff -uN --color=auto --label \"target: $target\" --label \"link: $link\" \\
      -- \"$target\" \"$link\" >&2 || true
    while :; do
      printf 'gx-sb: %s(l) is newer than %s(t).  Keep [l]ink file, [t]arget, or [s]kip? ' \\
        \"$link\" \"$target\" >&2
      read -r ans || ans=s
      case $ans in
        l|L)
          mkdir -p \"$(dirname \"$target\")\"
          if cat \"$link\" > \"$target\"; then break; fi
          echo \"gx-sb: could not write $target; left $link as is\" >&2
          return 0 ;;
        t|T) break ;;
        s|S) echo \"gx-sb: left $link as is\" >&2; return 0 ;;
      esac
    done
  fi
  ln -sfn \"$target\" \"$link\"
}
")

(define link-calls
  (string-join (map (match-lambda
                      ((link . target) (string-append "link_file "
                                                      (if (string-prefix? "/"
                                                           link)
                                                          (sh-quote link)
                                                          (string-append
                                                           "\"$HOME\"/"
                                                           (sh-quote link)))
                                                      " "
                                                      (sh-quote target))))
                    links) "\n"))

(define teardown
  (string-join (append (if (null? links)
                           '()
                           (list link-calls)) teardown-snippets) "\n"))

(define bootstrap
  (string-append "set -eo pipefail\n"
                 "cd "
                 (sh-quote container-project-dir)
                 "\n"
                 (if (null? links) ""
                     (string-append link-function link-calls "\n"))
                 "export SHELL=\"$GUIX_ENVIRONMENT\"/bin/"
                 (sh-quote shell)
                 "\n"
                 (string-join setup-snippets "\n")
                 "\n"
                 (if (string-null? teardown) "exec \"$@\"\n"
                     ;; Not exec: stay around to tidy up.  A trap (not an ignore, which
                     ;; children would inherit) keeps Ctrl-C from killing us first.
                     (string-append "trap : INT TERM HUP\n"
                                    "set +e\n\"$@\"\nrc=$?\nset -e\n" teardown
                                    "\n" "exit $rc\n"))))

;;; ---- Enter ----------------------------------------------------------------

(define command
  (match (cdr (command-line))
    (() default-command)
    (args args)))

(apply execlp
       "guix"
       "guix"
       "shell"
       "--container"
       "--emulate-fhs"
       "--no-cwd"
       (string-append "--manifest=" manifest-file)
       (string-append "--user=" container-user)
       (string-append "--share=" project-dir "=" container-project-dir)
       (string-append "--share=" home-dir "="
                      (container-home))
       (append (map (match-lambda
                      ((h . c) (string-append "--share=" h "=" c))) shares)
               (map (match-lambda
                      ((h . c) (string-append "--expose=" h "=" c))) exports)
               shell-flags
               (list "--" "env")
               (map (match-lambda
                      ((k . v) (string-append k "=" v))) env-vars)
               (list "bash" "-c" bootstrap "gx-sb")
               command))
