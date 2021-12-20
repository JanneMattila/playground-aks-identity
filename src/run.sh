#!/usr/bin/env bash

# Run once in every 10 minutes
UPDATE_FREQUENCY=600

while true; do
   echo "Running az cli based automation..."

   # Your logic here
   az login --identity
   az group list

   echo "Checking again in $UPDATE_FREQUENCY seconds."
   sleep "$UPDATE_FREQUENCY"
done
