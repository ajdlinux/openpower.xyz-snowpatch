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

# FIXME: This is a very dirty hack.
sudo /bin/rm -rf /var/lib/jenkins-slave/workspace/snowpatch/snowpatch-patchwork/patchwork/tools/docker/db/data/

echo ENV=$ENV > .env
docker-compose -f docker-compose-pg.yml build | tee ../patchwork-build.log
docker-compose -f docker-compose-pg.yml run web --quick-tox | tee ../patchwork-test.log
docker-compose down -v

# FIXME: This is a very dirty hack.
# Sudoers entry:
#   jenkins-slave ALL=(root) NOPASSWD: /bin/rm -rf /var/lib/jenkins-slave/workspace/snowpatch/snowpatch-patchwork/patchwork/tools/docker/db/data/
sudo /bin/rm -rf /var/lib/jenkins-slave/workspace/snowpatch/snowpatch-patchwork/patchwork/tools/docker/db/data/

# Timestamp for build
echo "Build completed, $(date)"

if grep "ERROR" ../patchwork-test.log
then
	exit 1
else
	exit 0
fi

# FIXME: detect errors in docker-compose build
