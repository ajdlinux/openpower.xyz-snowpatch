#!/bin/bash

# This build script is for running the Jenkins builds using docker.
#

# Trace bash processing
#set -x

# Default variables
WORKSPACE="${WORKSPACE:-${HOME}/${RANDOM}${RANDOM}}"
http_proxy="${http_proxy:-}"
DEFCONFIG_TO_USE=${DEFCONFIG_TO_USE:-pseries_le_defconfig}
GIT_REF_BASE=${GIT_REF_BASE:-master}
GIT_REF_PATCHED=${GIT_REF_PATCHED:-master}

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
	bison \
	flex \
	u-boot-tools

RUN apt-add-repository -y multiverse && apt-get update && apt-get install -yy \
	dwarves \
	sparse

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

# Go into the linux directory (the script will put us in a build subdir)
cd linux

# Record the version in the logs
gcc --version || exit 1

# Build kernel prep
make clean || exit 1
make mrproper || exit 1

# Start with the base branch
git checkout ${GIT_REF_BASE} || exit 1
git pull

# Build kernel with debug
make ${DEFCONFIG_TO_USE} || exit 1
echo "CONFIG_DEBUG_INFO=y" >> .config
make olddefconfig || exit 1
make -j$(nproc) -s C=2 CF=-D__CHECK_ENDIAN__ 2>>build_old.log >>build_old.log || exit 1

# Switch to the patched branch
git checkout ${GIT_REF_PATCHED} || exit 1

# Build again, should be minimal
make olddefconfig || exit 1
make -j$(nproc) -s C=1 CF=-D__CHECK_ENDIAN__ 2>>build_new.log >>build_new.log || exit 1

EOF_SCRIPT

chmod a+x "${WORKSPACE}/build.sh"

# Run the docker container, execute the build script we just built
docker run --cap-add=sys_admin --net=host --rm=true -e WORKSPACE="${WORKSPACE}" --user="${USER}" \
  -w "${HOME}" -v "${HOME}":"${HOME}" -t linux-build/ubuntu "${WORKSPACE}/build.sh"

# Timestamp for build
echo "Build completed, $(date)"

