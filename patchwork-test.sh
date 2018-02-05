#!/bin/bash

# This build script is for running the Jenkins builds using docker.
#

# Trace bash processing
#set -x

# Default variables
WORKSPACE="${WORKSPACE:-${HOME}/${RANDOM}${RANDOM}}"

# Timestamp for job
echo "Build started, $(date)"

mkdir -p "${WORKSPACE}"

sed -i "s/UID=1000/UID=$UID/g" patchwork/tools/docker/Dockerfile
cd patchwork
docker-compose build
docker-compose run --rm web --tox
docker-compose rm -fs

# Timestamp for build
echo "Build completed, $(date)"

