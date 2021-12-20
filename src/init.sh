#!/usr/bin/env bash

cat >/etc/motd <<EOF
Azure CLI based automation demo

GitHub: https://github.com/JanneMattila/playground-aks-identity
EOF

cat /etc/motd

# Run the main application
$@
