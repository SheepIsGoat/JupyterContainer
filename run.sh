#!/bin/bash

COMMAND=$1  # The first argument, should be 'up', 'down', or 'build'

if [ -z "$COMMAND" ]; then
    echo "No command specified. Usage: ./script.sh [up|down|build]"
    exit 1
fi

if [ -z "$TOKEN" ]; then
    TOKEN="passwd"
fi
GPU=nvidia
DIR_NAME=$(basename "$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)")
DIR_NAME=${DIR_NAME,,}  # make lowercase
IMG="${DIR_NAME}_${GPU}_jupyterbox"

case $COMMAND in
    up)
        IMAGE_NAME="$IMG" GPU=$GPU docker-compose -f docker/nvidia/docker-compose.yml up &
        
        URL="http://127.0.0.1:8888/lab?token=$TOKEN"
        while ! curl -s $URL > /dev/null; do
            echo "Waiting for $URL to become available..."
            sleep 1
        done
        
        xdg-open $URL
        ;;
    down)
        IMAGE_NAME="$IMG" GPU=$GPU docker-compose -f docker/nvidia/docker-compose.yml down
        ;;
    build)
        IMAGE_NAME="$IMG" GPU=$GPU docker-compose -f docker/nvidia/docker-compose.yml build
        ;;
    *)
        echo "Invalid command. Usage: ./script.sh [up|down|build]"
        exit 1
        ;;
esac
