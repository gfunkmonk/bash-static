#!/usr/bin/env bash

set -eo pipefail

OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)

OUTPUT=""
URL=""

if [[ "$OS_NAME" == "Linux" ]]; then
    case "$OS_ARCH" in
        x86_64)
            if command -v apt >/dev/null 2>&1; then
                OUTPUT="zig-master_0.17.0-dev.deb"
                URL="https://github.com/gfunkmonk/zig-master-debian/releases/download/0.17.0-dev.1640%2B2597da025/zig-master_0.17.0-dev.1640+2597da025-forky_amd64.deb"
            else
                OUTPUT="zig-master_0.17.0-dev.tar.xz"
                URL="https://ziglang.org/builds/zig-x86_64-linux-0.17.0-dev.1640+2597da025.tar.xz"
            fi
            ;;
        arm)
            OUTPUT="zig-master_0.17.0-dev-arm.tar.xz"
            URL="https://ziglang.org/builds/zig-arm-linux-0.17.0-dev.1640+2597da025.tar.xz"
            ;;
        aarch64)
            OUTPUT="zig-master_0.17.0-dev-aarch64.tar.xz"
            URL="https://ziglang.org/builds/zig-aarch64-linux-0.17.0-dev.1640+2597da025.tar.xz"
            ;;
        *)
            echo "ERROR: Unsupported Linux architecture: $OS_ARCH" >&2
            exit 1
            ;;
    esac
elif [[ "$OS_NAME" == "Darwin" ]]; then
    case "$OS_ARCH" in
        arm64|aarch64)
            OUTPUT="zig-master_0.17.0-dev-macos-aarch64.tar.xz"
            URL="https://ziglang.org/builds/zig-aarch64-macos-0.17.0-dev.1640+2597da025.tar.xz"
            ;;
        x86_64)
            OUTPUT="zig-master_0.17.0-dev-macos-x86_64.tar.xz"
            URL="https://ziglang.org/builds/zig-x86_64-macos-0.17.0-dev.1640+2597da025.tar.xz"
            ;;
        *)
            echo "ERROR: Unsupported macOS architecture: $OS_ARCH" >&2
            exit 1
            ;;
    esac
else
    echo "ERROR: Unsupported platform: $OS_NAME/$OS_ARCH" >&2
    exit 1
fi

if [[ -z "${OUTPUT:-}" ]] || [[ -z "${URL:-}" ]]; then
    echo "ERROR: Unsupported platform: $OS_NAME/$OS_ARCH" >&2
    exit 1
fi

if command -v aria2c >/dev/null 2>&1; then
    aria2c --max-tries=5 --retry-wait=10 -x 8 -s 8 --summary-interval=0 -c -o "$OUTPUT" "$URL" || exit 1
else
    curl -L -C - --progress-bar --retry 5 --output "$OUTPUT" "$URL" || exit 1
fi
