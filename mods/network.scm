(add-packages! "nss-certs")
(add-shell-flags! "--network")
(add-setup! "export PATH=\"$HOME/.local/bin:$PATH\""
            "export SSL_CERT_DIR=\"$GUIX_ENVIRONMENT/etc/ssl/certs\""
            "export SSL_CERT_FILE=\"$SSL_CERT_DIR/ca-certificates.crt\"")
