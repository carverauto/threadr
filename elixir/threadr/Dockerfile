FROM hexpm/elixir:1.19.5-erlang-28.4-debian-bookworm-20260223 AS builder

ENV MIX_ENV=prod \
    ERL_FLAGS="+JPperf true" \
    LANG=C.UTF-8

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
      build-essential \
      ca-certificates \
      curl \
      git && \
    rm -rf /var/lib/apt/lists/*

RUN curl https://sh.rustup.rs -sSf | sh -s -- -y --profile minimal --default-toolchain stable

ENV PATH="/root/.cargo/bin:${PATH}"

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod

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
