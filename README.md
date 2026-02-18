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

For BSD targets (FreeBSD, NetBSD, DragonFlyBSD, OpenBSD), you can use either:

1. **Prebuilt musl cross-compilation toolchains** (default with `--dl-toolchain`)
2. **Zig as a cross-compiler** (recommended with `--use-zig`)

### Using Zig for BSD Targets

Zig provides a simpler cross-compilation experience for all BSD targets:

```bash
# NetBSD
./build.sh --use-zig netbsd x86_64
./build.sh --use-zig netbsd aarch64

# FreeBSD
./build.sh --use-zig freebsd x86_64
./build.sh --use-zig freebsd aarch64

# OpenBSD
./build.sh --use-zig openbsd x86_64
./build.sh --use-zig openbsd riscv64

# DragonFlyBSD
./build.sh --use-zig dragonfly x86_64
```

Benefits of using Zig:
- Single toolchain for all targets
- No need to download/maintain separate cross-compilers
- Simpler setup and better BSD support
- Automatic fallback to traditional toolchain if unavailable

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
