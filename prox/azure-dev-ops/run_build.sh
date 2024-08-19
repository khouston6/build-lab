#!/bin/bash

# Get kernel version
KERNEL_VERSION=$(uname -r)

# Check if headers exist on server
ssh user@windows_server "if exist Z:\kernel_headers\$KERNEL_VERSION (exit 0) else (exit 1)"
HEADERS_EXIST=$?

if [ $HEADERS_EXIST -ne 0 ]; then
    # Package and transfer headers
    tar -czf /tmp/kernel_headers.tar.gz /lib/modules/$KERNEL_VERSION/build
    scp /tmp/kernel_headers.tar.gz user@windows_server:Z:\kernel_headers\$KERNEL_VERSION.tar.gz
    ssh user@windows_server "mkdir Z:\kernel_headers\$KERNEL_VERSION && tar -xzf Z:\kernel_headers\$KERNEL_VERSION.tar.gz -C Z:\kernel_headers\$KERNEL_VERSION"
fi

# Trigger Azure DevOps pipeline
curl -X POST \
  -H "Content-Type: application/json" \
  -H "Authorization: Basic ${AZURE_DEVOPS_PAT}" \
  --data "{\"definition\": {\"id\": 1}, \"parameters\": \"{\\\"KERNEL_VERSION\\\": \\\"$KERNEL_VERSION\\\"}\"}" \
  "https://dev.azure.com/{organization}/{project}/_apis/build/builds?api-version=6.0"
