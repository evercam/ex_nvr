FROM hexpm/elixir:1.18.3-erlang-27.3.3-debian-bullseye-20250428-slim

# install build dependencies
RUN \
  apt-get update && mkdir -p /etc/apt/keyrings \
  && apt-get install -y curl gpg \
  && curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg \
  && echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" | tee /etc/apt/sources.list.d/nodesource.list \
  && apt-get update \
  && apt-get install -y \
  libssl-dev \
  wget \
  xz-utils \
  nodejs \
  git \
  make \
  cmake \
  libsrtp2-dev \
  libturbojpeg-dev \
  && mkdir /opt/ffmpeg \
  && wget -O ffmpeg.tar.xz "https://github.com/BtbN/FFmpeg-Builds/releases/download/autobuild-2025-04-30-13-13/ffmpeg-n6.1.2-27-ge16ff06adb-linuxarm64-gpl-shared-6.1.tar.xz" \
  && tar -xvf ffmpeg.tar.xz -C /opt/ffmpeg --strip-components=1 \
  && rm -rf ffmpeg.tar.xz /var/lib/apt/lists/*

ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS
ENV MIX_ENV=prod
ENV GENERATE_DEB_PACKAGE=true

# Needed to compile Xav
ENV PKG_CONFIG_PATH=/opt/ffmpeg/lib/pkgconfig
ENV CPATH=/opt/ffmpeg/include
ENV LIBRARY_PATH=/opt/ffmpeg/lib

# Create build workdir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# install mix dependencies
COPY ui ui
RUN rm -rf ui/priv/bundlex ui/assets/node_modules

WORKDIR /app/ui

RUN mix deps.get
RUN mix deps.compile

RUN mix sentry.package_source_code
RUN mix release

RUN mkdir build-assets
RUN cp _build/prod/*.tar.gz _build/prod/*.deb build-assets/