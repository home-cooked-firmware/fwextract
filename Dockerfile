# Build image
#
# Compiles tools required for `fwextract` image:
#
# - OpenixCard (https://github.com/YuzukiTsuru/OpenixCard)
# - Unpackbootimg (https://github.com/anestisb/android-unpackbootimg)
FROM ubuntu:22.04 AS fwextract-builder
ARG DEBIAN_FRONTEND=noninteractive
ENV TERM=xterm

ARG UNPACKBOOTIMG_GIT_SHA=813a5e9a5aca12a5acc801df711da22baf64952d
ARG OPENIXCARD_GIT_SHA=2f1b1c7ce4cf883badb860ccc84c052854ee769b
# Unpackbootimg `master` 2023-04-03
# OpenixCard v1.1.8

# Install dependencies required to build `unpackbootimg` and `Openixcard`.
RUN apt-get update \
  && apt-get install -y \
  autoconf \
  automake \
  build-essential \
  cmake \
  git \
  libconfuse-dev \
  pkg-config \
  ssh \
  && rm -rf /var/cache/apt/* \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# Download and build `unpackbootimg`.
RUN git clone https://github.com/anestisb/android-unpackbootimg.git /unpackbootimg-src \
  && cd /unpackbootimg-src \
  && git checkout "$UNPACKBOOTIMG_GIT_SHA" \
  && make

# Download and build `OpenixCard`.
RUN git clone https://github.com/YuzukiTsuru/OpenixCard.git /openixcard-src \
  && cd /openixcard-src \
  && git checkout "$OPENIXCARD_GIT_SHA" \
  && git submodule init \
  && git submodule update \
  && mkdir /openixcard-src/build \
  && cd /openixcard-src/build \
  && cmake .. \
  && make

# Copy compiled binaries to fwextract bin dir.
RUN mkdir /fwextract-bin \
  && cp /unpackbootimg-src/mkbootimg /fwextract-bin/mkbootimg \
  && cp /unpackbootimg-src/unpackbootimg /fwextract-bin/unpackbootimg \
  && cp /openixcard-src/build/dist/OpenixCard /fwextract-bin/OpenixCard

# Copy `fwextract.sh` script to fwextract bin dir, make it executable.
COPY scripts/fwextract.sh /fwextract-bin/fwextract
RUN chmod +x /fwextract-bin/fwextract

# `fwextract` script image.
#
# Runs firmware extract script, but can optionally be used to access `unpackbootimg`,
# `mkbootimg`, and `OpenixCard` utilities directly.
FROM ubuntu:22.04 AS fwextract

VOLUME /fwextract-configs
VOLUME /fwextract-input
VOLUME /fwextract-output

# Install `libconfuse` which is required to run OpenixCard.
# Install tools and dependencies required for firmware extraction.
#
# - `coreutils`: Includes `dd` command to extract firmware
# - `fdisk`: Used to identify partition offsets and sizes
RUN apt-get update \
  && apt-get install -y \
  coreutils \
  fdisk \
  && rm -rf /var/cache/apt/* \
  && rm -rf /var/lib/apt/lists/* \
  && apt-get clean

# Copy binaries built by `fwextract-builder` to `/usr/bin`.
# Copy `fwextract.sh` from repo `scripts` directory to `/usr/bin/fwextract`.
COPY --from=fwextract-builder /fwextract-bin/mkbootimg /usr/bin/mkbootimg
COPY --from=fwextract-builder /fwextract-bin/unpackbootimg /usr/bin/unpackbootimg
COPY --from=fwextract-builder /fwextract-bin/OpenixCard /usr/bin/OpenixCard
COPY --from=fwextract-builder /fwextract-bin/fwextract /usr/bin/fwextract

CMD fwextract
