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
	PROXY2="ENV http_proxy ${http_proxy}"
	PROXY3="ENV https_proxy ${https_proxy}"
fi

Dockerfile=$(cat << EOF
FROM ubuntu:20.10

${PROXY}
${PROXY2}
${PROXY3}

RUN sed -Ei 's/^# deb-src /deb-src /' /etc/apt/sources.list

ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -yy \
	bc \
	build-essential \
	git \
	software-properties-common \
	libssl-dev \
	bison \
	flex \
	u-boot-tools \
	ccache \
	wget

RUN apt-add-repository -y multiverse && apt-get update && apt-get install -yy \
	dwarves \
	&& apt-get build-dep -yy sparse

# Install a new sparse from upstream
RUN wget -O /tmp/sparse-latest.tar.gz https://mirrors.edge.kernel.org/pub/software/devel/sparse/dist/sparse-latest.tar.gz && \
	cd /tmp && tar xf sparse-latest.tar.gz && cd sparse* && make -j4 PREFIX=/ install

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

sparse --version > sparse_version.txt

# XXX just for testing
ls -l /ccache
echo $CCACHE_DIR

# Record the version in the logs
gcc --version || exit 2

# Build kernel prep
make clean || exit 2
make mrproper || exit 2

git checkout "${GIT_REF_BASE}" || exit 2

# Build kernel with debug
make "${DEFCONFIG_TO_USE}" || exit 2
#echo "CONFIG_DEBUG_INFO=y" >> .config
make olddefconfig || exit 2
make CC="ccache gcc" -j$(nproc) -s C=2 CF="-D__CHECK_ENDIAN__ >> sparse_old.log 2>&1" 2>>build_old.log >>build_old.log || exit 2

# Switch to the patched branch
git checkout "${GIT_REF_PATCHED}" || exit 1
git reset --hard "origin/${GIT_REF_PATCHED}"

# Clean everything up
make clean || exit 1
make mrproper || exit 1
make "${DEFCONFIG_TO_USE}" || exit 1

# Build again with the changes applied
make olddefconfig || exit 1
make CC="ccache gcc" -j$(nproc) -s C=1 CF="-D__CHECK_ENDIAN__ >> sparse_new.log 2>&1" 2>>build_new.log >>build_new.log || exit 1

EOF_SCRIPT

chmod a+x "${WORKSPACE}/build.sh"

# Run the docker container, execute the build script we just built
docker run --cap-add=sys_admin --net=host --rm=true -e WORKSPACE="${WORKSPACE}" -e CCACHE_DIR=/ccache \
    --user="${USER}" -w "${HOME}" -v "${HOME}":"${HOME}" -v /ccache:/ccache -t linux-build/ubuntu \
    "${WORKSPACE}/build.sh"
result=$?

# Timestamp for build
echo "Build completed, $(date)"
exit $result
