#!/usr/bin/env bash

cat >/etc/motd <<EOF
 AZ CLI based automation demo

GitHub: https://github.com/JanneMattila/playground-aks-identity
Docker Hub: https://hub.docker.com/r/jannemattila/webapp-remote-access
EOF

cat /etc/motd

# Run the main application
$@
