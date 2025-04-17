FROM hexpm/elixir:1.17.3-erlang-27.3.3-alpine-3.18.9 AS build

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
  libjpeg-turbo-dev \
  linux-headers

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
COPY rtsp rtsp
COPY ui ui

WORKDIR /app/ui

RUN mix deps.get
RUN mix deps.compile

# compile and build release
RUN mix do compile, release

# prepare release image
FROM alpine:3.18.9 AS app

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
  coreutils \
  util-linux

WORKDIR /app

RUN mkdir /var/lib/ex_nvr
RUN chown nobody:nobody /app /var/lib/ex_nvr

USER nobody:nobody

COPY --from=build --chown=nobody:nobody /app/ui/_build/prod/rel/ex_nvr ./

ENV HOME=/app

EXPOSE 4000

HEALTHCHECK CMD curl --fail http://localhost:4000 || exit 1  

COPY --chown=nobody:nobody entrypoint.sh ./entrypoint.sh

RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]

CMD ["bin/ex_nvr", "start"]