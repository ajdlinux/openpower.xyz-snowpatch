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
docker-compose build | tee ../patchwork-build.log
docker-compose run --rm web --quick-tox | tee ../patchwork-test.log
docker-compose down

# Timestamp for build
echo "Build completed, $(date)"

if grep "ERROR" ../patchwork-test.log
then
	exit 1
else
	exit 0
fi

# FIXME: detect errors in docker-compose build
