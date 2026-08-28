# Stage 1: Build WebUI assets
FROM node:22-alpine AS webui-builder
WORKDIR /app/webui
COPY webui/package*.json ./
RUN npm ci
COPY webui/ ./
RUN npm run build

# Stage 2: Build Zig backend
FROM alpine:3.20 AS zig-builder
WORKDIR /app

RUN apk add --no-cache curl xz tar jq build-base musl-dev

# Install Zig 0.15.0 (nightly/dev 0.15 required for std.io.Writer.Allocating)
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
COPY --from=webui-builder /app/webui/dist ./webui/dist

RUN zig build -Doptimize=ReleaseSafe --summary all

# Stage 3: Minimal runtime image
FROM alpine:3.20
WORKDIR /app

RUN apk add --no-cache curl openssl ca-certificates tzdata

COPY --from=zig-builder /app/zig-out/bin/zed2api /app/zed2api

EXPOSE 8001

ENTRYPOINT ["/app/zed2api", "serve", "8001"]
