(add-packages! "xorg-server-xwayland")
(let* ((socket-path (mk-path
                  (get-host-env "XDG_RUNTIME_DIR" #f)
                  (get-host-env "WAYLAND_DISPLAY" #f)))
       (sock (socket AF_UNIX SOCK_STREAM 0)))
      (connect sock AF_UNIX socket-path)
      (fcntl sock F_SETFD 0)
      (add-env! "DISPLAY" ":1")
      (add-setup! (string-append
                    "WAYLAND_SOCKET="
                    (number->string (fileno sock))
                    " Xwayland :1 -geometry 1920x1080 2>/dev/null &")
                  ""))
