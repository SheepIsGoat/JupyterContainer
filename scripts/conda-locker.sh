#!/bin/bash


GPU=nvidia
ENV_YAML_PATH="docker/${GPU}/environment.yaml"

# Check if environment.yml is provided
if [ "$#" -ne 0 ]; then
    ENV_YAML_PATH=$1
fi
ENV_NAME=$(grep 'name:' $ENV_YAML_PATH | cut -d ' ' -f 2)
echo "Using environment.yaml at path $ENV_YAML_PATH with name $ENV_NAME"

# Docker image to use
DOCKER_IMAGE="continuumio/miniconda3"
CONTAINER_NAME="conda-locker"

# Check if the container already exists
EXISTING_CONTAINER=$(docker ps -q -f name=$CONTAINER_NAME)

if [ -z "$EXISTING_CONTAINER" ]; then
    # Start a new Docker container if it doesn't exist
    CONTAINER_ID=$(docker run -d -it --name $CONTAINER_NAME --rm $DOCKER_IMAGE /bin/bash)
else
    # Use the existing container
    CONTAINER_ID=$EXISTING_CONTAINER
fi

# Install conda-lock in the container (if not already installed)
# Check if conda-lock is installed
if ! docker exec $CONTAINER_ID conda list conda-lock; then
    # Install conda-lock if not found
    docker exec $CONTAINER_ID conda install -c conda-forge conda-lock -y
fi


# Copy the environment.yml to the container
docker cp $ENV_YAML_PATH $CONTAINER_ID:/environment.yml

# Generate the conda-lock file
LOCKFILE_NAME="${ENV_NAME}-conda-lock.yml"  #-linux-64.conda-lock"
if docker exec $CONTAINER_ID conda-lock -f /environment.yml -p linux-64; then
    # Copy the conda-lock file back to the host
    docker cp $CONTAINER_ID:/conda-lock.yml ./docker/${GPU}/$LOCKFILE_NAME
    echo "Conda-lock file generated: $LOCKFILE_NAME"
else
    echo "Failed to generate the conda-lock file."
fi
