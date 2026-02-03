#!/bin/bash

set -eo pipefail
shopt -s nullglob

usage() {
    latest=$(basename --suffix .sh "$(readlink version.sh 2>/dev/null || echo "version.sh")")
    bv=${latest##version-}
    cat << __USAGE
$(basename "${0}") [OS] [ARCH] [TAG]

Where:
  OS   -- defaults to $(uname -s | tr '[:upper:]' '[:lower:]')
  ARCH -- defaults to $(uname -m | tr '[:upper:]' '[:lower:]')
  TAG  -- defaults to ${bv}

Environment variables:
  DL_TOOLCHAIN       -- Use prebuilt musl cross-compiler toolchain from github
  NOSIG              -- Set to skip GPG signature verification (not recommended)
  EXTRA_CFLAGS       -- Additional compiler flags to append to default CFLAGS
  WITH_TESTS         -- Build with tests
  KEEP_BUILD         -- Don't clean up build directory on success
  NJOBS              -- Number of parallel jobs (default: auto-detect)
__USAGE
}

TOOLCHAIN_DL="https://github.com/gfunkmonk/musl-cross/releases/download/02032026"

# Color definitions
NC="\033[0m"
RED="\033[1;31m"
GREEN="\033[1;32m"
YELLOW="\033[1;33m"
BLUE="\033[1;34m"
PURPLE="\033[1;35m"
CYAN="\033[1;36m"
BROWN="\033[0;33m"
TEAL="\033[2;36m"
BWHITE="\033[1;37m"
DKPURPLE="\033[0;35m"
WHITE="\033[0;37m"
LIME="\033[38;2;204;255;0m"
JUNEBUD="\033[38;2;189;218;87m"
CORAL="\033[38;2;255;127;80m"
PINK="\033[38;2;255;45;192m"
HOTPINK="\033[38;2;255;105;180m"
ORANGE="\033[38;2;255;165;0m"
PEACH="\033[38;2;246;161;146m"
GOLD="\033[38;2;255;215;0m"
NAVAJO="\033[38;2;255;222;173m"
LEMON="\033[38;2;255;244;79m"
CANARY="\033[38;2;255;255;153m"
KHAKI="\033[38;2;226;214;167m"
CRIMSON="\033[38;2;220;20;60m"
TAWNY="\033[38;2;204;78;0m"
ORCHID="\033[38;2;218;112;214m"
HELIOTROPE="\033[38;2;223;115;255m"
SLATE="\033[38;2;109;129;150m"
LAGOON="\033[38;2;142;235;236m"
PLUM="\033[38;2;142;69;133m"
VIOLET="\033[38;2;143;0;255m"
LIGHTROYAL="\033[38;2;10;148;255m"
TURQUOISE="\033[38;2;64;224;208m"
MINT="\033[38;2;152;255;152m"
AQUA="\033[38;2;18;254;202m"
SKY="\033[38;2;135;206;250m"
TOMATO="\033[38;2;255;99;71m"
CREAM="\033[38;2;255;253;208m"
REBECCA="\033[38;2;102;51;153m"

# Silence pushd/popd
pushd() { command pushd "$@" >/dev/null; }
popd() { command popd >/dev/null; }

# Get number of parallel jobs
get_parallel_jobs() {
    if [[ -n ${NJOBS:-} ]]; then
        echo "$NJOBS"
    elif command -v nproc >/dev/null 2>&1; then
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.physicalcpu
    else
        echo "1"
    fi
}

# Download and verify files with GPG signatures
mycurl() {
    (($# == 2)) || return 1
    local url=$1
    local sig_ext=$2
    local filename=${url##*/}

    # Download main file if not cached
    if [[ ! -f ${filename} ]]; then
        echo -e "${HELIOTROPE}Downloading: ${filename}${NC}"
        echo -e "${TAWNY}  URL: ${url}${NC}"
        curl -sSfLO "$url" || return 1
    else
        echo -e "${BWHITE}Using cached: ${filename}${NC}"
    fi

    # Handle signature verification
    if [[ ! ${NOSIG:-} ]]; then
        # Download signature file if not cached
        if [[ ! -f ${filename}.${sig_ext} ]]; then
            echo -e "${HELIOTROPE}Downloading signature: ${filename}.${sig_ext}${NC}"
            echo -e "${GOLD}  URL: ${url}.${sig_ext}${NC}"
            curl -sSfLO "${url}.${sig_ext}" || {
                echo -e "${RED}ERROR: Failed to download signature file${NC}" >&2
                return 1
            }
        fi

        # Verify signature
    echo -e "${DKPURPLE}Verifying signature: ${filename}${NC}"
    gpg --trust-model always --verify "${filename}.${sig_ext}" "${filename}" 2>/dev/null || {
        echo -e "${CRIMSON}ERROR: GPG verification failed for ${filename}${NC}" >&2
        return 1
        }
        echo -e "${GREEN}Signature verified for ${filename}"
    else
        echo -e "${YELLOW}WARNING: Skipping signature verification (NOSIG is set)${NC}" >&2
    fi
}

# Helper function for robust GPG key import
import_gpg_key() {
    local key=$1
    local keyservers=(
        "hkps://keyserver.ubuntu.com:443"
        "hkps://keys.openpgp.org"
        "keyserver.ubuntu.com"
        "keyring.debian.org"
        "pgp.mit.edu"
        "185.125.188.27"
        "hkp://ipv4.pool.sks-keyservers.net"
    )

    # Check if key already exists
    if gpg --quiet --list-keys "$key" >/dev/null 2>&1; then
        echo -e "${CRIMSON}GPG key ${key} already imported${NC}"
        return 0
    fi

    echo -e "${SLATE}Importing GPG key: ${key}${NC}"
    for i in {1..3}; do
        for server in "${keyservers[@]}"; do
            if gpg --quiet --keyserver "$server" --recv-keys "$key" 2>/dev/null; then
                echo -e "${PLUM}Successfully imported key from $server${NC}"
                return 0
            fi
        done
        [[ $i -lt 3 ]] && sleep 3
    done

    echo -e "${RED}ERROR: Failed to import GPG key ${key}${NC}" >&2
    return 1
}

# Normalize architecture names
normalize_arch() {
    local raw_arch=$1
    case "$raw_arch" in
        arm64|armv8) echo "aarch64" ;;
        armv6l) echo "armv6" ;;
        armv7l) echo "armv7" ;;
        i386|x32) echo "i686" ;;
        openrisc) echo "or1k" ;;
        ppc) echo "powerpc" ;;
        ppcle) echo "powerpcle" ;;
        ppc64) echo "powerpc64" ;;
        ppc64le) echo "powerpc64le" ;;
        risc|risc32) echo "riscv32" ;;
        risc64) echo "riscv64" ;;
        x86-64|amd64|x64) echo "x86_64" ;;
        *) echo "$raw_arch" ;;
    esac
}

# Get per-architecture default CFLAGS
get_arch_cflags() {
    local arch=$1
    case "$arch" in
        aarch64) echo "-march=armv8-a" ;;
        armv5) echo "-march=armv5te -mtune=arm946e-s -mfloat-abi=soft" ;;
        armv6) echo "-march=armv6 -mfloat-abi=hard -mfpu=vfp" ;;
        armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
        i486) echo "-march=i486 -mtune=generic" ;;
        i586) echo "-march=i586 -mtune=generic" ;;
        i686) echo "-march=i686 -mtune=generic" ;;
        loongarch64) echo "-march=loongarch64" ;;
        m68k) echo "-march=68020 -fomit-frame-pointer -ffreestanding" ;;
        mips64) echo "-march=mips64 -mabi=64" ;;
        mips64el) echo "-mplt" ;;
        powerpc) echo "-mpowerpc -m32" ;;
        powerpcle) echo "-m32" ;;
        powerpc64) echo "-mpowerpc64 -m64 -falign-functions=32 -falign-labels=32 -falign-loops=32 -falign-jumps=32" ;;
        powerpc64le) echo "-m64" ;;
        riscv64) echo "-march=rv64gc -mabi=lp64d" ;;
        riscv32) echo "-ffreestanding -Wno-implicit-function-declaration -Wno-int-conversion" ;;
        x86_64) echo "-march=x86-64 -mtune=generic" ;;
        *) echo "" ;;
    esac
}

# Get musl toolchain name for architecture
get_musl_toolchain() {
    local arch=$1
    case "$arch" in
        aarch64) echo "aarch64-unknown-linux-musl" ;;
        armv5) echo "armv5-unknown-linux-musleabi" ;;
        armv6) echo "armv6-unknown-linux-musleabihf" ;;
        armv7) echo "armv7-unknown-linux-musleabihf" ;;
        i486) echo "i486-unknown-linux-musl" ;;
        i586) echo "i586-unknown-linux-musl" ;;
        i686) echo "i686-unknown-linux-musl" ;;
        loongarch64) echo "loongarch64-unknown-linux-musl" ;;
        m68k) echo "m68k-unknown-linux-musl" ;;
        microblaze) echo "microblaze-xilinx-linux-musl" ;;
        mips) echo "mips-unknown-linux-muslsf" ;;
        mipsel) echo "mipsel-unknown-linux-muslsf" ;;
        mips64) echo "mips64-unknown-linux-musl" ;;
        mips64el) echo "mips64el-unknown-linux-musl" ;;
        or1k) echo "or1k-unknown-linux-musl" ;;
        powerpc) echo "powerpc-unknown-linux-muslsf" ;;
        powerpcle) echo "powerpcle-unknown-linux-muslsf" ;;
        powerpc64) echo "powerpc64-unknown-linux-musl" ;;
        powerpc64le) echo "powerpc64le-unknown-linux-musl" ;;
        riscv64) echo "riscv64-unknown-linux-musl" ;;
        riscv32) echo "riscv32-unknown-linux-musl" ;;
        s390x) echo "s390x-ibm-linux-musl" ;;
        sh4) echo "sh4-multilib-linux-musl" ;;
        x86_64) echo "x86_64-linux-musl" ;;
       *) echo "" ;;
    esac
}

# Get host triplet for cross-compilation
get_host_triplet() {
    local arch=$1
    local toolchain_name=$(get_musl_toolchain "$arch")
    echo "$toolchain_name"
}

# Download and setup musl prebuilt toolchain
setup_musl_toolchain() {
    local arch=$1
    local toolchain_name=$(get_musl_toolchain "$arch")

    if [[ -z "$toolchain_name" ]]; then
        echo -e "${YELLOW}No prebuilt toolchain available for ${arch}, falling back to building musl${NC}"
        return 1
    fi

    local toolchain_dir="${PWD}/toolchain-${toolchain_name}"
    local toolchain_bin="${toolchain_dir}/bin/${toolchain_name}-gcc"
    local toolchain_strip="${toolchain_dir}/bin/${toolchain_name}-strip"

    # Check if already downloaded
    if [[ -f "$toolchain_bin" ]]; then
        echo -e "${LAGOON}= Reusing existing ${toolchain_name} toolchain${NC}"
        export CC="${toolchain_bin}"
        export PATH="${toolchain_dir}/bin:${PATH}"
        export STRIPCMD="${toolchain_strip}"
        return 0
    fi

    echo -e "${CANARY}= Downloading ${toolchain_name} toolchain${NC}"
    local toolchain_url="${TOOLCHAIN_DL}/${toolchain_name}.tar.xz"
    local archive_name="${toolchain_name}.tar.xz"

    # Download toolchain
    if ! curl -sSfL "${toolchain_url}" -o "$archive_name"; then
        echo -e "${YELLOW}Failed to download toolchain from github, falling back to building musl${NC}"
        return 1
    fi

    echo -e "${KHAKI}= Extracting ${toolchain_name} toolchain${NC}"
    mkdir -p "$toolchain_dir"

    # Extract based on archive type (silent extraction)
    tar -xJf "$archive_name" -C "$toolchain_dir" --strip-components=1 2>/dev/null || {
    echo -e "${RED}ERROR: Failed to extract toolchain${NC}" >&2
        rm -rf "$toolchain_dir" "$archive_name"
    return 1
    }

    # Verify the compiler exists
    if [[ ! -f "$toolchain_bin" ]]; then
        echo -e "${RED}ERROR: Toolchain extraction failed, compiler not found${NC}" >&2
        rm -rf "$toolchain_dir"
        return 1
    fi

    echo -e "${BWHITE}= Setting CC to ${toolchain_name}-gcc${NC}"
    export CC="${toolchain_bin}"
    export PATH="${toolchain_dir}/bin:${PATH}"
    export STRIPCMD="${toolchain_strip}"

    # Cleanup tarball
    rm -f "$archive_name"

    return 0
}

main() {
    [[ ${1} = '-h' || ${1} = '--help' || ${1} = 'help' ]] && usage && exit 0
    [[ ${1} = 'clean' ]] && rm -fr build/ && rm -fr releases/ && echo -e "${ORANGE} Cleaned build/ and releases/ !!" && exit 0

    myT=$(uname -s) && dO=$(echo "$myT" | tr '[:upper:]' '[:lower:]')
    myA=$(uname -m) && dA=$(echo "$myA" | tr '[:upper:]' '[:lower:]')

    declare -r target=${1:-$dO}
    declare -r arch=$(normalize_arch "${2:-$dA}")
    declare -r tag=${3:-}
    declare -r musl_mirror='https://musl.libc.org/releases'

    echo -e "${BWHITE}Building for: ${VIOLET}OS=${target}, ${TOMATO}ARCH=${arch}${NC}"

    # Ensure we are in the project root
    pushd "${0%/*}"

    # Load version info
    version_file="./version${tag:+-$tag}.sh"
    if [[ ! -f "$version_file" ]]; then
        echo -e "${RED}ERROR: Version file not found: $version_file${NC}" >&2
        exit 1
    fi

    # shellcheck source=version.sh
    source "$version_file"

    # Validate required variables
    if [[ -z ${bash_version:-} ]]; then
        echo -e "${RED}ERROR: bash_version not set in $version_file${NC}" >&2
        exit 1
    fi

    # Make build directory
    mkdir -p build && pushd build

    # Prepare GPG for verification (skip if NOSIG is set)
    if [[ ! ${NOSIG:-} ]]; then
    echo -e "${LEMON}= Preparing GPG${NC}"
    export GNUPGHOME=${PWD}/.gnupg
    mkdir -p "$GNUPGHOME"
    chmod 700 "$GNUPGHOME"

    # Import public keys
    import_gpg_key 7C0135FB088AAF6C66C650B9BB5869F064EA74AB || exit 2  # bash
    import_gpg_key 836489290BB6B70F99FFDA0556BCDB593020450F || exit 2  # musl
    else
        echo -e "${YELLOW}WARNING: Skipping GPG setup (NOSIG is set)${NC}" >&2
    fi

    # Download bash tarball
    echo -e "${BWHITE}= Downloading bash ${bash_version}${NC}"
    bash_mirrors=(
        "https://ftp.gnu.org/gnu/bash"
        "https://mirrors.ocf.berkeley.edu/gnu/bash"
        "https://mirrors.kernel.org/gnu/bash"
        "https://mirrors.ibiblio.org/pub/mirrors/gnu/bash"
        "https://mirror.us-midwest-1.nexcess.net/gnu/bash"
    )

    bash_downloaded=false
    for mirror in "${bash_mirrors[@]}"; do
        if mycurl "${mirror}/bash-${bash_version}.tar.gz" sig; then
            bash_downloaded=true
            break
        fi
        echo -e "${YELLOW}Failed to download from $mirror, trying next...${NC}"
    done

    if [[ $bash_downloaded == false ]]; then
        echo -e "${RED}ERROR: Failed to download bash from all mirrors${NC}" >&2
        exit 1
    fi

    # Extract bash
    echo -e "${HOTPINK}= Extracting bash ${bash_version}${NC}"
    rm -rf bash-"${bash_version}"
    tar -xf "bash-${bash_version}.tar.gz"

    # Apply official patches
    if [[ ${bash_patch_level:-0} -gt 0 ]]; then
        echo -e "${CYAN}= Patching bash ${bash_version} | patches: ${bash_patch_level}${NC}"
        for ((lvl = 1; lvl <= bash_patch_level; lvl++)); do
            printf -v bash_patch 'bash%s-%03d' "${bash_version/\./}" "${lvl}"

            # Try downloading patch from mirrors
            patch_downloaded=false
            for mirror in "${bash_mirrors[@]}"; do
                if mycurl "${mirror}/bash-${bash_version}-patches/${bash_patch}" sig; then
                    patch_downloaded=true
                    break
                fi
                echo -e "${YELLOW}Failed to download patch from $mirror, trying next...${NC}"
            done

            if [[ $patch_downloaded == false ]]; then
                echo -e "${RED}WARNING: Failed to download patch ${bash_patch} from all mirrors${NC}" >&2
                continue
            fi

            pushd bash-"${bash_version}"
            patch -sp0 <../"${bash_patch}" || {
                echo -e "${RED}WARNING: Failed to apply patch ${bash_patch}${NC}" >&2
            }
            popd
        done
    fi

    # Apply custom patches
    echo -e "${AQUA}= Applying custom patches${NC}"
    for patch in ../custom/bash"${bash_version/\./}"*.patch; do
        if [[ -f "$patch" ]]; then
            echo -e "${CREAM}Applying ${patch##*/}${NC}"
            pushd bash-"${bash_version}"
            patch -sp1 < ../"${patch}" || {
                echo -e "${RED}WARNING: Failed to apply custom patch ${patch##*/}${NC}" >&2
            }
            popd
        fi
    done

    # Configure arguments
    configure_args=(--enable-silent-rules)
    host_arg=""

    # Platform-specific setup
    if [[ $target == linux ]]; then
        if . /etc/os-release 2>/dev/null && [[ ${ID:-} == alpine ]]; then
            echo -e "${BWHITE}= Skipping installation of musl (already installed on Alpine)${NC}"
        elif [[ ${DL_TOOLCHAIN:-} ]]; then
            # Try to use prebuilt toolchain
            if setup_musl_toolchain "$arch"; then
                echo -e "${GREEN}= Successfully configured musl toolchain${NC}"

                # Set host argument for cross-compilation
                host_arg="--host=$(get_host_triplet "$arch")"

                # Add -std=gnu17 for musl toolchain compatibility
                export CFLAGS="-std=gnu17 ${CFLAGS:-}"
        else
                # Fallback to building musl if toolchain download fails
                echo -e "${CORAL}= Building musl from source${NC}"
                install_dir=${PWD}/musl-install-${musl_version}
            if [[ -f ${install_dir}/bin/musl-gcc ]]; then
                echo -e "${LAGOON}= Reusing existing musl ${musl_version}${NC}"
            else
                echo -e "${CANARY}= Downloading musl ${musl_version}${NC}"
                mycurl ${musl_mirror}/musl-"${musl_version}".tar.gz asc

                echo -e "${KHAKI}= Extracting musl ${musl_version}${NC}"
                rm -rf musl-"${musl_version}"
                tar -xf musl-"${musl_version}".tar.gz

                echo -e "${CORAL}= Building musl ${musl_version}${NC}"
                pushd musl-"${musl_version}"
                ./configure --prefix="${install_dir}" "${configure_args[@]}"
                make -j"$(nproc)" -s install
                popd # musl-${musl_version}
                rm -rf musl-"${musl_version}"
            fi
                echo -e "${BWHITE}= Setting CC to musl-gcc ${musl_version}${NC}"
                export CC=${install_dir}/bin/musl-gcc
            fi
        else
            # Default: build musl from source
            install_dir=${PWD}/musl-install-${musl_version}
            if [[ -f ${install_dir}/bin/musl-gcc ]]; then
                echo -e "${LAGOON}= Reusing existing musl ${musl_version}${NC}"
            else
                echo -e "${CANARY}= Downloading musl ${musl_version}${NC}"
                mycurl ${musl_mirror}/musl-"${musl_version}".tar.gz asc

                echo -e "${KHAKI}= Extracting musl ${musl_version}${NC}"
                rm -rf musl-"${musl_version}"
                tar -xf musl-"${musl_version}".tar.gz

                echo -e "${CORAL}= Building musl ${musl_version}${NC}"
                pushd musl-"${musl_version}"
                ./configure --prefix="${install_dir}" "${configure_args[@]}"
                make -j"$(nproc)" -s install
                popd # musl-${musl_version}
                rm -rf musl-"${musl_version}"
            fi

            echo -e "${BWHITE}= Setting CC to musl-gcc ${musl_version}${NC}"
            export CC=${install_dir}/bin/musl-gcc
        fi

        # Linux-specific flags
        export CFLAGS="${CFLAGS:-} -Os -static -ffunction-sections -fdata-sections"
        export LDFLAGS="${LDFLAGS:-} -Wl,--gc-sections"

        # Add architecture-specific CFLAGS
        arch_cflags=$(get_arch_cflags "$arch")
        [[ -n $arch_cflags ]] && export CFLAGS="${CFLAGS} ${arch_cflags}"

        # Add custom CFLAGS if provided
        [[ -n ${EXTRA_CFLAGS:-} ]] && export CFLAGS="${CFLAGS} ${EXTRA_CFLAGS}"

    else
        echo -e "${BROWN}= WARNING: Your platform does not support static binaries.${NC}"
        echo -e "${BROWN}= (This is mainly due to non-static libc availability.)${NC}"

        if [[ $target == macos ]]; then
            # Set minimum version of macOS to 10.13
            export MACOSX_DEPLOYMENT_TARGET="10.13"
            export MACOS_TARGET="10.13"
            export CC="clang -std=c89 -Wno-return-type -Wno-implicit-function-declaration"
            export CXX="clang -std=c89 -Wno-return-type -Wno-implicit-function-declaration"
            # Use included gettext to avoid reading from other places, like homebrew
            configure_args=("${configure_args[@]}" "--with-included-gettext")

            # If $arch is aarch64 for mac, target arm64
            if [[ $arch == aarch64 ]]; then
                export CFLAGS="-Os -target arm64-apple-macos"
                host_arg="--host=aarch64-apple-darwin"
                # Add custom CFLAGS if provided
                [[ -n ${EXTRA_CFLAGS:-} ]] && export CFLAGS="${CFLAGS} ${EXTRA_CFLAGS}"
            #else
                #export CFLAGS="${CFLAGS:-} -Os -target x86_64-apple-macos10.12"
                #host_arg="--host=x86_64-apple-macos10.12"
            fi
        fi
    fi

    if [[ $arch == mipsel ]]; then
       host_arg="--host=mipsel-unknown-linux-muslsf"
    fi

    echo -e "${BLUE}===========${REBECCA} Configuration: ${BLUE}=============${NC}"
    echo -e "${TEAL}= Building bash ${bash_version}${NC}"
    echo -e "${LIGHTROYAL}  CFLAGS: ${CFLAGS:-none}${NC}"
    echo -e "${TURQUOISE}  LDFLAGS: ${LDFLAGS:-none}${NC}"
    echo -e "${MINT}  Host: ${host_arg:-native}${NC}"
    [[ -f "$STRIPCMD" ]] && echo -e "${SKY}  strip: $STRIPCMD${NC}"
    [[ -n ${WITH_TESTS:-} ]] && echo -e " ${BWHITE} Build Tests: ${PINK}yes${NC}" || echo -e " ${BWHITE} Build Tests: ${LIME}no${NC}"
    echo -e "${BLUE}========================================${NC}"

    pushd bash-"${bash_version}"

    export CPPFLAGS="${CFLAGS}" # Some versions need both set
    autoconf -f && ./configure --without-bash-malloc "${configure_args[@]}" "${host_arg}"

    # Parallel build based on platform
    make -j"$(get_parallel_jobs)" -s
    [[ -n ${WITH_TESTS:-} ]] && make -j"$(get_parallel_jobs)" tests -s

    popd # bash-${bash_version}
    popd # build

    echo -e "${PURPLE}= Extracting bash ${bash_version} binary${NC}"
    mkdir -p releases
    cp build/bash-"${bash_version}"/bash releases/bash-"${bash_version}"-"${arch}"

    # Strip binary based on architecture and platform
    if [[ -f "$STRIPCMD" ]]; then
        echo -e "${LIME}= Stripping binary${NC}"
        "${STRIPCMD}" -s releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
    elif [[ "$arch" == "mipsel" ]]; then
        echo -e "${LIME}= Stripping binary (mipsel)${NC}"
        mipsel-linux-muslsf-strip -s releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
    elif [[ "$target" != "macos" ]]; then
        echo -e "${LIME}= Stripping binary${NC}"
        strip -s releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
    else
        echo -e "${LIME}= Stripping binary (macOS)${NC}"
        strip -S releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
    fi

    # Clean up build directory unless KEEP_BUILD is set
    if [[ ! ${KEEP_BUILD:-} ]]; then
        echo -e "${HELIOTROPE}Cleaning up build directory"
        rm -rf build/bash-"${bash_version}"
    fi

    # Compress with UPX (skip on macOS)
    if [[ "$target" != "macos" ]] && command -v upx >/dev/null 2>&1; then
        echo -e "${ORANGE}= Compressing with UPX${NC}"
        upx --ultra-brute releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
    else
        echo -e "${PINK}= Skipping UPX compression (not installed)${NC}"
    fi

    # Display results
    echo ""
    echo -e "${NAVAJO}========================================${NC}"
    echo -e "${NAVAJO}=         Build Complete! ✓            =${NC}"
    echo -e "${NAVAJO}========================================${NC}"
    echo -e "${PEACH}  Output: releases/bash-${bash_version}-${arch}${NC}"
    echo -e "${JUNEBUD}  Size: $(du -h releases/bash-"${bash_version}"-"${arch}" 2>/dev/null | cut -f1 || echo 'unknown')${NC}"

    # Show binary info
    if command -v file >/dev/null 2>&1; then
        echo -e "${ORCHID}  Type: $(file releases/bash-"${bash_version}"-"${arch}" | cut -d: -f2-)${NC}"
    fi

    echo -e "${GREEN}= Done ${NC}"
    echo -e "${LEMON}Build completed successfully!${NC}"

    popd # project root
}

# Only execute if not being sourced
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi