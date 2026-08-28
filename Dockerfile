# Stage 1: Build WebUI assets
FROM node:22-slim AS webui-builder
WORKDIR /app/webui
COPY webui/package*.json ./
RUN npm ci
COPY webui/ ./
RUN npm run build

# Stage 2: Build Zig backend on Ubuntu
FROM ubuntu:24.04 AS zig-builder
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    xz-utils \
    tar \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install official Zig 0.15.2 release
ARG ZIG_VERSION=0.15.2
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ZIG_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then ZIG_ARCH="aarch64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -fL "https://ziglang.org/download/${ZIG_VERSION}/zig-${ZIG_ARCH}-linux-${ZIG_VERSION}.tar.xz" -o zig.tar.xz && \
    mkdir -p /opt/zig && \
    tar -xf zig.tar.xz -C /opt/zig --strip-components=1 && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz && \
    zig version

COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY --from=webui-builder /app/webui/dist/ /app/webui/dist/

RUN zig build -Doptimize=ReleaseSafe --summary all

# Stage 3: Minimal runtime image
FROM ubuntu:24.04
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    openssl \
    ca-certificates \
    tzdata \
    && rm -rf /var/lib/apt/lists/*

COPY --from=zig-builder /app/zig-out/bin/zed2api /app/zed2api

EXPOSE 8001

ENTRYPOINT ["/app/zed2api", "serve", "8001"]
