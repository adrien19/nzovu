#!/bin/bash

set -euo pipefail

go mod download
make init-proto
go install github.com/fullstorydev/grpcurl/cmd/grpcurl@latest

# Install Node.js dependencies for the frontend

# Check if Node.js is installed
if ! command -v node &> /dev/null
then
    echo "Node.js could not be found, installing Node.js"
    curl -fsSL https://deb.nodesource.com/setup_24.x | sudo bash -
    sudo apt install nodejs -y
fi
# Now check node and npm versions
echo "Node.js version: $(node --version)"
echo "npm version: $(npm --version)"
# install pnpm if not installed
if ! command -v pnpm &> /dev/null
then
    echo "pnpm could not be found, installing pnpm"
    sudo npm install -g pnpm
fi
# Check pnpm version
echo "pnpm version: $(pnpm --version)"
