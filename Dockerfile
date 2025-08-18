# Cerebros container image
# Multi-stage build: builder (fetch deps + compile) then runtime slim image

ARG ELIXIR_VERSION=1.15.7
ARG OTP_VERSION=26.2.5
ARG ALPINE_VERSION=3.19

# -------- Builder Stage --------
FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-alpine-${ALPINE_VERSION} AS builder

# Install build tools & git
RUN apk add --no-cache build-base git bash openssh curl

# Enable CUDA build if passed at build time: --build-arg EXLA_TARGET=cuda
ARG EXLA_TARGET=host
ENV EXLA_TARGET=${EXLA_TARGET}

# Set working directory
WORKDIR /app

# Install hex & rebar (already in official images usually)
RUN mix local.hex --force && mix local.rebar --force

# Copy mix files and fetch deps first (layer caching)
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get

# Compile deps (respect EXLA_TARGET)
RUN mix deps.compile

# Copy the rest of app source
COPY lib lib
COPY iex.md README_ELIXIR.md ./

# Build release (we'll use an OTP release rather than escript for runtime flexibility)
RUN MIX_ENV=prod mix compile
RUN MIX_ENV=prod mix release cerebros

# -------- Runtime Stage --------
FROM alpine:${ALPINE_VERSION} AS runtime

# Install runtime dependencies (libstdc++, bash for convenience)
RUN apk add --no-cache libstdc++ bash ncurses-libs

# Copy release from builder
WORKDIR /app
COPY --from=builder /app/_build/prod/rel/cerebros ./cerebros

# Provide default env (override EXLA_TARGET at runtime if GPU container base used)
ENV EXLA_TARGET=host
ENV MIX_ENV=prod

# Expose no network ports by default (CLI tool). Add if you later create a service.
# EXPOSE 4000

# Entrypoint wrapper: allow calling CLI commands. Eg:
# docker run --rm cerebros search --num-trials 5 --epochs 3
ENTRYPOINT ["/app/cerebros/bin/cerebros"]
CMD ["start"]
