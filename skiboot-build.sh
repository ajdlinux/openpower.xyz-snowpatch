#!/bin/bash

# This build script is for running the Jenkins builds using docker.
#

# Trace bash processing
#set -x

# Default variables
WORKSPACE="${WORKSPACE:-${HOME}/${RANDOM}${RANDOM}}"
http_proxy="${http_proxy:-}"

# Timestamp for job
echo "Build started, $(date)"

# Configure docker build
if [[ -n "${http_proxy}" ]]; then
PROXY="RUN echo \"Acquire::http::Proxy \\"\"${http_proxy}/\\"\";\" > /etc/apt/apt.conf.d/000apt-cacher-ng-proxy"
fi

Dockerfile=$(cat << EOF
FROM ppc64le/ubuntu:16.04

${PROXY}

ENV DEBIAN_FRONTEND noninteractive 
RUN apt-get update && apt-get install -yy \
	bc \
	build-essential \
	git \
	software-properties-common \
	libssl-dev \
	valgrind \
	device-tree-compiler

RUN grep -q ${GROUPS} /etc/group || groupadd -g ${GROUPS} ${USER}
RUN grep -q ${UID} /etc/passwd || useradd -d ${HOME} -m -u ${UID} -g ${GROUPS} ${USER}

USER ${USER}
ENV HOME ${HOME}
RUN /bin/bash
EOF
)

# Build the docker container
docker build -t linux-build/ubuntu - <<< "${Dockerfile}"
if [[ "$?" -ne 0 ]]; then
  echo "Failed to build docker container."
  exit 1
fi

# Create the docker run script
export PROXY_HOST=${http_proxy/#http*:\/\/}
export PROXY_HOST=${PROXY_HOST/%:[0-9]*}
export PROXY_PORT=${http_proxy/#http*:\/\/*:}

mkdir -p "${WORKSPACE}"

cat > "${WORKSPACE}/build.sh" << EOF_SCRIPT
#!/bin/bash

set -x
set -o pipefail

cd "${WORKSPACE}"

# Go into the skibinutils-powerpc64-linux-gnuboot directory (the script will put us in a build subdir)
cd skiboot

# Record the version in the logs
gcc --version || exit 1

# Build prep
CROSS= make clean || exit 1

# Build skiboot
CROSS= make -j >> build.log || exit 1

# Test skiboot
CROSS= make check >> check.log || exit 1
EOF_SCRIPT

chmod a+x "${WORKSPACE}/build.sh"

# Run the docker container, execute the build script we just built
docker run --cap-add=sys_admin --net=host --rm=true -e WORKSPACE="${WORKSPACE}" --user="${USER}" \
  -w "${HOME}" -v "${HOME}":"${HOME}" -t linux-build/ubuntu "${WORKSPACE}/build.sh"

# Timestamp for build
echo "Build completed, $(date)"

