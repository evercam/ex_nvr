FROM hexpm/elixir:1.15.7-erlang-26.1.2-debian-bullseye-20231009-slim

# install build dependencies
RUN \
  apt-get update && apt-get install -y \
  npm \
  git \
  make \
  cmake \
  libsrtp2-dev \
  libturbojpeg-dev \ 
  && rm -rf /var/lib/apt/lists/*

ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS
ENV MIX_ENV=prod

# Create build workdir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY assets assets
COPY apps apps
COPY rel rel

RUN mix deps.get
RUN mix deps.compile

RUN cd apps/ex_nvr_web/assets && npm install
RUN cd apps/ex_nvr_web && mix assets.deploy

RUN mix do release