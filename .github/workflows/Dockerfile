FROM hexpm/elixir:1.17.3-erlang-27.2-debian-bullseye-20241202-slim

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
  && rm -rf /var/lib/apt/lists/*

ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS
ENV MIX_ENV=prod
ENV GENERATE_DEB_PACKAGE=true

# Create build workdir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# install mix dependencies
COPY rtsp rtsp
COPY ui ui
RUN rm -rf ui/priv/bundlex ui/assets/node_modules

WORKDIR /app/ui

RUN mix deps.get
RUN mix deps.compile

RUN mix release

RUN mkdir build-assets
RUN cp _build/prod/*.tar.gz _build/prod/*.deb build-assets/