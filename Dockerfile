# Cerebros container image
# Multi-stage build: builder (fetch deps + compile) then runtime slim image

ARG ELIXIR_VERSION=1.15.7
ARG BUILDER_IMAGE=elixir:${ELIXIR_VERSION}

# -------- Builder Stage --------
FROM ${BUILDER_IMAGE} AS builder

# Install build tools & git (Debian based official Elixir image)
RUN apt-get update && \
	apt-get install -y --no-install-recommends build-essential git curl bash ca-certificates openssh-client && \
	rm -rf /var/lib/apt/lists/*

# Enable CUDA build if passed at build time: --build-arg EXLA_TARGET=cuda
ARG EXLA_TARGET=host
ENV EXLA_TARGET=${EXLA_TARGET}

# Set working directory
WORKDIR /app

# Install hex & rebar (already in official images usually)
RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod
# Copy mix files and fetch deps first (layer caching)
COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV

RUN mix deps.compile

COPY lib lib
COPY iex.md ./

# Build release (we'll use an OTP release rather than escript for runtime flexibility)
RUN mix compile
RUN mix release cerebros

# -------- Runtime Stage --------
FROM debian:bookworm-slim AS runtime

# Install runtime dependencies (libstdc++, bash for convenience)
RUN apt-get update && \
	apt-get install -y --no-install-recommends libstdc++6 bash ca-certificates curl && \
	rm -rf /var/lib/apt/lists/*

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
