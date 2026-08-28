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

# build-base / musl-dev is required for Zig when link_libc = true
RUN apk add --no-cache curl xz tar jq build-base musl-dev

# Automatically resolve and install official Zig 0.14.0 / 0.15 matching CPU arch
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "x86_64" ]; then ZIG_ARCH="x86_64"; \
    elif [ "$ARCH" = "aarch64" ]; then ZIG_ARCH="aarch64"; \
    else echo "Unsupported architecture: $ARCH" && exit 1; fi && \
    curl -fL "https://ziglang.org/download/0.14.0/zig-linux-${ZIG_ARCH}-0.14.0.tar.xz" -o zig.tar.xz && \
    mkdir -p /opt/zig && \
    tar -xf zig.tar.xz -C /opt/zig --strip-components=1 && \
    ln -s /opt/zig/zig /usr/local/bin/zig && \
    rm zig.tar.xz && \
    zig version

COPY build.zig build.zig.zon ./
COPY src/ ./src/
COPY --from=webui-builder /app/webui/dist ./webui/dist

RUN zig build -Doptimize=ReleaseSafe --summary all

# Stage 3: Minimal runtime image
FROM alpine:3.20
WORKDIR /app

# Runtime dependencies: curl (streaming/proxy calls), openssl (cryptographic operations), ca-certificates
RUN apk add --no-cache curl openssl ca-certificates tzdata

COPY --from=zig-builder /app/zig-out/bin/zed2api /app/zed2api

EXPOSE 8001

ENTRYPOINT ["/app/zed2api", "serve", "8001"]
