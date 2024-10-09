FROM hexpm/elixir:1.15.7-erlang-26.1.2-alpine-3.18.4 AS build

# install build dependencies
RUN \
  apk add --no-cache \
  build-base \
  npm \
  git \
  make \
  cmake \
  openssl-dev \ 
  ffmpeg-dev \
  clang-dev \
  libsrtp-dev \
  libjpeg-turbo-dev

ARG VERSION
ENV VERSION=${VERSION}
ENV DOCKER_BUILD=true

ARG ERL_FLAGS
ENV ERL_FLAGS=$ERL_FLAGS

# Create build workdir
WORKDIR /app

# install hex + rebar
RUN mix local.hex --force && \
  mix local.rebar --force

# set build ENV
ENV MIX_ENV=prod

# install mix dependencies
COPY mix.exs mix.lock ./
COPY config config
COPY assets assets
COPY apps apps
COPY rel rel

RUN mix deps.get
RUN mix deps.compile

# compile and build release
RUN mix do compile, release

# prepare release image
FROM alpine:3.18.5 AS app

# install runtime dependencies
RUN \
  apk add --no-cache \
  openssl \
  ncurses-libs \
  ffmpeg \
  clang \ 
  curl \
  libsrtp \
  libjpeg-turbo \
  coreutils

WORKDIR /app

RUN mkdir /var/lib/ex_nvr
RUN chown nobody:nobody /app /var/lib/ex_nvr

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/_build/prod/rel/ex_nvr ./

ENV HOME=/app

EXPOSE 4000

HEALTHCHECK CMD curl --fail http://localhost:4000 || exit 1  

COPY --chown=nobody:nobody entrypoint.sh ./entrypoint.sh

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

CMD ["bin/ex_nvr", "start"]