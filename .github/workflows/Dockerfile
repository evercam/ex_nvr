FROM hexpm/elixir:1.19.5-erlang-28.1.1-debian-bullseye-20260112

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

COPY video_processor video_processor
COPY ui ui
RUN rm -rf ui/assets/node_modules

WORKDIR /app/ui

RUN mix deps.get
RUN mix deps.compile

RUN mix sentry.package_source_code
RUN mix release

RUN mkdir build-assets
RUN cp _build/prod/*.tar.gz _build/prod/*.deb build-assets/