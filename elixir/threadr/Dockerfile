FROM hexpm/elixir:1.17.3-erlang-27.1.2-debian-bookworm-20241016 AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      cargo \
      curl \
      git \
      rustc && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod
RUN mix deps.compile

COPY priv priv
COPY assets assets
COPY lib lib
COPY native native

RUN mix compile
RUN mix assets.deploy
RUN mix release

FROM debian:bookworm-slim AS runner

ENV LANG=C.UTF-8 \
    MIX_ENV=prod \
    PHX_SERVER=true \
    HOME=/app

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      ca-certificates \
      libstdc++6 \
      openssl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /app

COPY --from=builder /app/_build/prod/rel/threadr ./

EXPOSE 4000

CMD ["bin/threadr", "start"]
