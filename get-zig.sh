#!/usr/bin/env bash

set -eo pipefail

OS_NAME=$(uname -s)
OS_ARCH=$(uname -i)

if [[ "$OS_NAME" == "Linux" ]] && [[ "$OS_ARCH" == "x86_64" ]]; then
    if command -v apt >/dev/null 2>&1; then
        OUTPUT="zig-master_0.16.0-dev.deb"
        URL="https://github.com/gfunkmonk/zig-master-debian/releases/download/1.0/zig-master_0.16.0-dev.2565+684032671-1+forky_amd64.deb"
    else
        OUTPUT="zig-master_0.16.0-dev.tar.xz"
        URL="https://ziglang.org/builds/zig-x86_64-linux-0.16.0-dev.2670+56253d9e3.tar.xz"
    fi
fi

if command -v aria2c >/dev/null 2>&1; then
    aria2c --max-tries=5 --retry-wait=10 -x 8 -s 8 --summary-interval=0 -c -o "$OUTPUT" "$URL" || return 1
else
    curl -L -C - --progress-bar --retry 5 --output "$OUTPUT"  "$URL"
fi
