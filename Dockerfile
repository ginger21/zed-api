# Stage 1: Build WebUI assets
FROM node:22-slim AS webui-builder
WORKDIR /app/webui
COPY webui/package*.json ./
RUN npm ci
COPY webui/ ./
RUN npm run build

# Stage 2: Build Zig backend on Ubuntu (native glibc environment)
FROM ubuntu:24.04 AS zig-builder
WORKDIR /app

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    xz-utils \
    tar \
    jq \
    build-essential \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Install Zig master (0.15.x)
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ZIG_TARGET="x86_64-linux"; \
    elif [ "$ARCH" = "aarch64" ]; then ZIG_TARGET="aarch64-linux"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    ZIG_URL=$(curl -s https://ziglang.org/download/index.json | jq -r ".master.\"${ZIG_TARGET}\".tarball") && \
    curl -fL "$ZIG_URL" -o zig.tar.xz && \
    mkdir -p /opt/zig && \
    tar -xf zig.tar.xz -C /opt/zig --strip-components=1 && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz && \
    zig version

COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY --from=webui-builder /app/webui/dist/ /app/webui/dist/

RUN ls -la /app/webui/dist/ && zig build -Doptimize=ReleaseSafe --summary all

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
