# bash-static

Because we all need the most static bash we can get in this world.

## Getting

Download from the Releases section or run `./build.sh`.

Note that you really can't have truly static binaries on Darwin or
Windows machines, because there are no static libraries that can be used.
But this will ensure that Darwin or Windows bash binaries will not rely on
anything else but their libcs.

On Linux, we use musl instead of glibc to avoid `dlopen()`.

## Cross-Compilation

This project supports multiple cross-compilation methods:

1. **Prebuilt musl cross-compilation toolchains** (for Linux/BSD, use `--dl-toolchain`)
2. **Zig as a universal cross-compiler** (recommended, use `--use-zig`)
3. **Native clang** (for macOS)
4. **Building musl from source** (default fallback)

### Using Zig for Cross-Compilation (Recommended)

Zig provides the simplest cross-compilation experience for all supported targets:

```bash
# Linux targets
./build.sh --use-zig linux x86_64
./build.sh --use-zig linux aarch64
./build.sh --use-zig linux armv7
./build.sh --use-zig linux riscv64

# macOS targets
./build.sh --use-zig macos x86_64
./build.sh --use-zig macos aarch64

# BSD targets
./build.sh --use-zig netbsd x86_64
./build.sh --use-zig freebsd aarch64
./build.sh --use-zig openbsd x86_64
./build.sh --use-zig dragonfly x86_64
```

**Benefits of using Zig:**
- Single universal toolchain for all targets (Linux, macOS, BSD)
- No need to download/maintain separate cross-compilers
- Built-in support for musl libc on Linux
- Simpler setup with automatic fallback to traditional toolchains
- Excellent support for all BSD variants

## Rationale

This started as an experiment in Jan 2015 when Glider Labs was testing the
viability of potentially using just a statically linked bash entrypoint
as the only entrance into a container. So the following works:

```sh
FROM scratch
ADD bash
ENTRYPOINT ['/bash']
```

Adding in busybox would make the container relatively feature-complete
for debugging or just for common tools. This works great with a
container image that has busybox (i.e `progrium/busybox`).

If you're not going for purely static minimalism, you can achieve a similar
result just by using Alpine today, also discovered during this experiment in 2015.

## License

MIT
