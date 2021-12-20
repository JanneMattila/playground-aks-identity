#!/usr/bin/env bash

cat >/etc/motd <<EOL 
     _
    | | __ _ _ __  _ __   ___
 _  | |/ _` | '_ \| '_ \ / _ \
| |_| | (_| | | | | | | |  __/
 \___/ \__,_|_| |_|_| |_|\___|
 AZ CLI based automation demo

GitHub: https://github.com/JanneMattila/playground-aks-identity
Docker Hub: https://hub.docker.com/r/jannemattila/webapp-remote-access

EOL
cat /etc/motd

# Run the main application
$@
