# Stage 1: Build WebUI assets
FROM node:20-alpine AS webui-builder
WORKDIR /app/webui
COPY webui/package*.json ./
RUN npm ci
COPY webui/ ./
RUN npm run build

# Stage 2: Build Zig backend
FROM alpine:3.20 AS zig-builder
WORKDIR /app

RUN apk add --no-cache curl xz tar jq

# Automatically resolve and install official Zig 0.15 (master) matching host CPU architecture
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ZIG_TARGET="x86_64-linux"; \
    elif [ "$ARCH" = "aarch64" ]; then ZIG_TARGET="aarch64-linux"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    ZIG_URL=$(curl -s https://ziglang.org/download/index.json | jq -r ".master.\"${ZIG_TARGET}\".tarball") && \
    if [ -z "$ZIG_URL" ] || [ "$ZIG_URL" = "null" ]; then \
      echo "Failed to fetch Zig download URL from ziglang.org" && exit 1; \
    fi && \
    echo "Downloading Zig from $ZIG_URL" && \
    curl -fL "$ZIG_URL" -o zig.tar.xz && \
    mkdir -p /opt/zig && \
    tar -xf zig.tar.xz -C /opt/zig --strip-components=1 && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz && \
    zig version

COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY --from=webui-builder /app/webui/dist/ ./webui/dist/

RUN zig build -Doptimize=ReleaseSafe

# Stage 3: Minimal runtime image
FROM alpine:3.20
WORKDIR /app

# Runtime dependencies: curl (streaming/proxy calls), openssl (cryptographic operations), ca-certificates
RUN apk add --no-cache curl openssl ca-certificates tzdata

COPY --from=zig-builder /app/zig-out/bin/zed2api /app/zed2api

EXPOSE 8001

ENTRYPOINT ["/app/zed2api", "serve", "8001"]
