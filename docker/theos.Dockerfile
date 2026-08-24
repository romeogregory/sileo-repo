# Reusable Theos build environment. Theos needs a Unix toolchain, so it cannot
# run natively on Windows; this image is the supported path for compiling
# anything under tweaks/.
#
#   docker build -f docker/theos.Dockerfile -t theos-builder .
#   docker run --rm -v "%cd%:/work" theos-builder tweaks/Pseudonym
#
# The image is ~3GB, almost all of it the Swift toolchain and the iOS SDK.
# Build it once; compiles afterwards take seconds.
FROM debian:bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential curl git perl zsh unzip xz-utils ca-certificates \
        file fakeroot python3 sudo \
    && rm -rf /var/lib/apt/lists/*

# Theos refuses to run as root.
RUN useradd --create-home --shell /bin/bash builder
USER builder
ENV THEOS=/home/builder/theos

RUN git clone --recursive --depth 1 https://github.com/theos/theos.git $THEOS

# install-theos wants an interactive confirmation before fetching the toolchain
# and SDKs, which a Docker build cannot give it, so both are pinned here.
#
# The tarball holds host/ and iphone/ at its root, so stripping one component
# into toolchain/linux puts clang exactly where Theos looks for it:
# $THEOS/toolchain/linux/iphone/bin/clang
RUN mkdir -p $THEOS/toolchain/linux \
    && curl -sL https://github.com/kabiroberai/swift-toolchain-linux/releases/download/v2.3.0/swift-5.8-ubuntu22.04.tar.xz \
       | tar -xJ --strip-components=1 -C $THEOS/toolchain/linux \
    && test -x $THEOS/toolchain/linux/iphone/bin/clang

# Only the iOS 16 SDK is extracted; the sdks repo carries every version.
RUN curl -sL https://github.com/theos/sdks/archive/refs/heads/master.tar.gz \
    | tar -xz --strip-components=1 -C $THEOS/sdks --wildcards '*/iPhoneOS16*.sdk' \
    && ls $THEOS/sdks

# Installed as its own layer purely to keep the expensive toolchain and SDK
# layers above cached. rsync is what Theos uses to stage layout/ into the
# package, so maintainer scripts are silently dropped without it.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
        rsync libplist-utils \
    && rm -rf /var/lib/apt/lists/*
COPY docker/build-tweak.sh /usr/local/bin/build-tweak
RUN chmod 0755 /usr/local/bin/build-tweak
USER builder

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/build-tweak"]
