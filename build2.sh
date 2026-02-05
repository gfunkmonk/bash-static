#!/bin/bash

set -eo pipefail
shopt -s nullglob

usage() {
    latest=$(basename --suffix .sh "$(readlink version.sh 2>/dev/null || echo "version.sh")")
    bv=${latest##version-}
echo ""
echo -e "${LIME}$(basename ${0}) ${GREEN}[${BWHITE}OPTIONS${GREEN}] [${BWHITE}OS${GREEN}] [${BWHITE}ARCH${GREEN}] [${BWHITE}TAG${GREEN}]${NC}"
echo ""
echo -e "${BWHITE}Where:${NC}"
echo -e "${JUNEBUD}  OS   ${NAVAJO}-- defaults to $(uname -s | tr '[:upper:]' '[:lower:]')${NC}"
echo -e "${TOMATO}  ARCH ${NAVAJO}-- defaults to $(uname -m | tr '[:upper:]' '[:lower:]') ${PINK}(ignored when using --batch)${NC}"
echo -e "${PINK}  TAG  ${NAVAJO}-- defaults to ${bv}${NC}"
echo ""
echo -e "${LAGOON}Options:                                                                   Environment Variables:${NC}"
echo -e "${MINT} --dl-toolchain      ${BWHITE}= Use prebuilt musl cross toolchain         ${SKY}[${GOLD}DL_TOOLCHAIN${SKY}]${NC}"
echo -e "${MINT} --batch ARCHS       ${BWHITE}= Build multiple archs (comma-separated)    ${SKY}[${GOLD}BATCH_ARCHS${SKY}]${NC}"
echo -e "${MINT} --nosig             ${BWHITE}= Skip GPG signature verification           ${SKY}[${GOLD}NOSIG${SKY}]${NC}"
echo -e "${MINT} --extra-cflags VAL  ${BWHITE}= Extra flags to append to default CFLAGS   ${SKY}[${GOLD}EXTRA_CFLAGS${SKY}]${NC}"
echo -e "${MINT} --aggressive        ${BWHITE}= Use aggressive CFLAGS                     ${SKY}[${GOLD}AGGRESSIVE_OPT${SKY}]${NC}"
echo -e "${MINT} --lto               ${BWHITE}= Enable LTO Optimization                   ${SKY}[${GOLD}USE_LTO${SKY}]${NC}"
echo -e "${MINT} --njobs VAL         ${BWHITE}= Number of parallel jobs (default: auto)   ${SKY}[${GOLD}NJOBS${SKY}]${NC}"
echo -e "${MINT} --ccache            ${BWHITE}= Use ccache if found                       ${SKY}[${GOLD}USE_CCACHE${SKY}]${NC}"
echo -e "${MINT} --cache-dir DIR     ${BWHITE}= Dir of cached downloads (default: .cache) ${SKY}[${GOLD}CACHE_DIR${SKY}]${NC}"
echo -e "${MINT} --parallel-extract  ${BWHITE}= Extract archives in parallel              ${SKY}[${GOLD}PARALLEL_EXTRACT${SKY}]${NC}"
echo -e "${MINT} --no-upx            ${BWHITE}= Skip UPX compression                      ${SKY}[${GOLD}NO_UPX${SKY}]${NC}"
echo -e "${MINT} --with-tests        ${BWHITE}= Build with tests                          ${SKY}[${GOLD}WITH_TESTS${SKY}]${NC}"
echo -e "${MINT} --keep-build        ${BWHITE}= Keep build dir on success                 ${SKY}[${GOLD}KEEP_BUILD${SKY}]${NC}"
echo -e "${MINT} --checksum          ${BWHITE}= Generate SHA256 checksums for releases    ${SKY}[${GOLD}GEN_CHECKSUM${SKY}]${NC}"
echo -e "${MINT} --profile           ${BWHITE}= Build profiling/timing                    ${SKY}[${GOLD}PROFILE_BUILD${SKY}]${NC}"
echo ""
echo -e "${GOLD}Examples:${NC}"
echo -e "${CYAN}  Single build:  ${BWHITE}./build.sh linux aarch64${NC}"
echo -e "${CYAN}  Batch build:   ${BWHITE}./build.sh --batch x86_64,aarch64,armv7 linux${NC}"
echo -e "${CYAN}  With options:  ${BWHITE}./build.sh --dl-toolchain --ccache --lto linux x86_64${NC}"
echo ""
}

TOOLCHAIN_DL="https://github.com/gfunkmonk/musl-cross/releases/download/02032026"
ROOTDIR="${PWD}"
CACHE_DIR="${CACHE_DIR:-.cache}"

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
SELAGO="\033[38;2;255;215;255m"
CHARTREUSE="\033[38;2;127;255;0m"

# Silence pushd/popd
pushd() { command pushd "$@" >/dev/null; }
popd() { command popd >/dev/null; }

# Timing functions for profiling
declare -A BUILD_TIMINGS
start_timer() {
    [[ -n ${PROFILE_BUILD:-} ]] && BUILD_TIMINGS["$1"]=$(date +%s)
}

end_timer() {
    if [[ -n ${PROFILE_BUILD:-} ]]; then
        local start=${BUILD_TIMINGS["$1"]:-0}
        local end=$(date +%s)
        local elapsed=$((end - start))
        echo -e "${SLATE}⏱  $1: ${elapsed}s${NC}"
    fi
}

# Get number of parallel jobs with better detection
get_parallel_jobs() {
    if [[ -n ${NJOBS:-} ]]; then
        echo "$NJOBS"
    elif command -v nproc >/dev/null 2>&1; then
        # Use all cores for extraction/patching, N-1 for compilation to avoid overload
        nproc
    elif command -v sysctl >/dev/null 2>&1; then
        sysctl -n hw.physicalcpu
    else
        echo "1"
    fi
}

# Setup ccache if requested and available
setup_ccache() {
    if [[ -n ${USE_CCACHE:-} ]] && command -v ccache >/dev/null 2>&1; then
        echo -e "${CANARY}= Setting up ccache${NC}"
        export CC="ccache ${CC}"
        export CCACHE_DIR="${PWD}/.ccache"
        mkdir -p "$CCACHE_DIR"
        ccache -M 2G >/dev/null 2>&1 || true
        echo -e "${GREEN}  ccache enabled${NC}"
        return 0
    fi
    return 1
}

# Enhanced download with caching
mycurl() {
    (($# == 2)) || return 1
    local url=$1
    local sig_ext=$2
    local filename=${url##*/}
    
    # Create cache directory
    mkdir -p "${CACHE_DIR}"
    
    # Check cache first
    local cache_file="${CACHE_DIR}/${filename}"
    if [[ -f ${cache_file} ]]; then
        echo -e "${BWHITE}Using cached: ${filename}${NC}"
        ln -sf "${cache_file}" "${filename}" 2>/dev/null || cp "${cache_file}" "${filename}"
    else
        # Download main file
        echo -e "${HELIOTROPE}Downloading: ${filename}${NC}"
        echo -e "${TAWNY}  URL: ${url}${NC}"
        
        # Use aria2c if available for faster downloads
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -x 8 -s 8 --summary-interval=0 --download-result=hide -d "$(dirname "${cache_file}")" -o "$(basename "${cache_file}")" "$url" || return 1
        else
            curl -sSfL --progress-bar -o "${cache_file}" "$url" || return 1
        fi
        
        # Link from cache to working directory
        ln -sf "${cache_file}" "${filename}" 2>/dev/null || cp "${cache_file}" "${filename}"
    fi

    # Handle signature verification
    if [[ ! ${NOSIG:-} ]]; then
        local cache_sig="${CACHE_DIR}/${filename}.${sig_ext}"
        
        # Download signature file if not cached
        if [[ ! -f ${cache_sig} ]]; then
            echo -e "${HELIOTROPE}Downloading signature: ${filename}.${sig_ext}${NC}"
            echo -e "${GOLD}  URL: ${url}.${sig_ext}${NC}"
            
            if command -v aria2c >/dev/null 2>&1; then
                aria2c -x 4 --summary-interval=0 --download-result=hide -d "$(dirname "${cache_sig}")" -o "$(basename "${cache_sig}")" "${url}.${sig_ext}" || {
                    echo -e "${RED}ERROR: Failed to download signature file${NC}" >&2
                    return 1
                }
            else
                curl -sSfLO -o "${cache_sig}" "${url}.${sig_ext}" || {
                    echo -e "${RED}ERROR: Failed to download signature file${NC}" >&2
                    return 1
                }
            fi
        fi
        
        # Link signature from cache
        ln -sf "${cache_sig}" "${filename}.${sig_ext}" 2>/dev/null || cp "${cache_sig}" "${filename}.${sig_ext}"

        # Verify signature
        echo -e "${DKPURPLE}Verifying signature: ${filename}${NC}"
        gpg --trust-model always --verify "${filename}.${sig_ext}" "${filename}" 2>/dev/null || {
            echo -e "${CRIMSON}ERROR: GPG verification failed for ${filename}${NC}" >&2
            return 1
        }
        echo -e "${GREEN}Signature verified for ${filename}${NC}"
    else
        echo -e "${YELLOW}WARNING: Skipping signature verification (NOSIG is set)${NC}" >&2
    fi
}

# Helper function for robust GPG key import with caching
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

# Download and setup musl prebuilt toolchain with caching
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
    local cache_archive="${CACHE_DIR}/${archive_name}"

    # Check cache
    mkdir -p "${CACHE_DIR}"
    if [[ -f "${cache_archive}" ]]; then
        echo -e "${BWHITE}Using cached toolchain: ${archive_name}${NC}"
        ln -sf "${cache_archive}" "${archive_name}" 2>/dev/null || cp "${cache_archive}" "${archive_name}"
    else
        # Download toolchain
        if command -v aria2c >/dev/null 2>&1; then
            aria2c -x 8 -s 8 --summary-interval=0 --download-result=hide -d "${CACHE_DIR}" -o "${archive_name}" "${toolchain_url}" || {
                echo -e "${YELLOW}Failed to download toolchain from github, falling back to building musl${NC}"
                return 1
            }
        else
            if ! curl -sSfL --progress-bar "${toolchain_url}" -o "${cache_archive}"; then
                echo -e "${YELLOW}Failed to download toolchain from github, falling back to building musl${NC}"
                return 1
            fi
        fi
        ln -sf "${cache_archive}" "${archive_name}" 2>/dev/null || cp "${cache_archive}" "${archive_name}"
    fi

    echo -e "${KHAKI}= Extracting ${toolchain_name} toolchain${NC}"
    mkdir -p "$toolchain_dir"

    # Extract with parallel decompression if available
    if [[ -n ${PARALLEL_EXTRACT:-} ]] && command -v pixz >/dev/null 2>&1; then
        pixz -d < "$archive_name" | tar -x -C "$toolchain_dir" --strip-components=1 2>/dev/null || {
            echo -e "${RED}ERROR: Failed to extract toolchain${NC}" >&2
            rm -rf "$toolchain_dir"
            return 1
        }
    else
        tar -xJf "$archive_name" -C "$toolchain_dir" --strip-components=1 2>/dev/null || {
            echo -e "${RED}ERROR: Failed to extract toolchain${NC}" >&2
            rm -rf "$toolchain_dir"
            return 1
        }
    fi

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

    return 0
}

# Build musl from source and set CC
build_musl_from_source() {
    start_timer "musl_build"
    echo -e "${CORAL}= Building musl from source${NC}"
    local install_dir=${PWD}/musl-install-${musl_version}-${arch}

    if [[ -f ${install_dir}/bin/musl-gcc ]]; then
        echo -e "${LAGOON}= Reusing existing musl ${musl_version}${NC}"
    else
        echo -e "${CANARY}= Downloading musl ${musl_version}${NC}"
        mycurl "${musl_mirror}/musl-${musl_version}.tar.gz" asc

        echo -e "${KHAKI}= Extracting musl ${musl_version}${NC}"
        rm -rf "musl-${musl_version}"
        
        # Parallel extraction if available
        if [[ -n ${PARALLEL_EXTRACT:-} ]] && command -v pigz >/dev/null 2>&1; then
            pigz -dc "musl-${musl_version}.tar.gz" | tar -x
        else
            tar -xzf "musl-${musl_version}.tar.gz"
        fi

        # Apply custom musl patches
        echo -e "\n"
        apply_patches_parallel "$ROOTDIR/custom/musl" "musl-${musl_version}" "*.patch"
        echo -e "\n"
        end_timer "patch_musl"

        echo -e "${CORAL}= Building musl ${musl_version}${NC}"
        pushd "musl-${musl_version}"

        ./configure --prefix="${install_dir}" "${configure_args[@]}"
        make -j"$(get_parallel_jobs)" -s install
        popd # musl-${musl_version}
        rm -rf "musl-${musl_version}"
    fi

    echo -e "${BWHITE}= Setting CC to musl-gcc ${musl_version}${NC}"
    export CC="${install_dir}/bin/musl-gcc"
    end_timer "musl_build"
}

# Parallel patch application
apply_patches_parallel() {
    local patch_dir=$1
    local target_dir=$2
    local patch_names=$3
    
    if [[ ! -d "$patch_dir" ]]; then
        return 0
    fi
    
    local patches=("${patch_dir}"/${patch_names})
    if [[ ${#patches[@]} -eq 0 ]]; then
        return 0
    fi
    
    echo -e "${AQUA}= Applying patches from ${patch_dir}${NC}"
    
    for patch in "${patches[@]}"; do
        if [[ -f "$patch" ]]; then
            echo -e "${CREAM}Applying ${patch##*/}${NC}"
            # Get absolute path to patch
            local abs_patch=$(cd "$(dirname "$patch")" && pwd)/$(basename "$patch")
            pushd "$target_dir" >/dev/null
            patch -sp1 --fuzz=4 < "${abs_patch}" || {
                echo -e "${RED}WARNING: Failed to apply patch ${patch##*/}${NC}" >&2
            }
            popd >/dev/null
        fi
    done
}

# Generate checksums for release binaries
generate_checksums() {
    local release_dir=$1
    echo -e "${VIOLET}= Generating SHA256 checksums${NC}"
    pushd "$release_dir"
    for binary in bash-*; do
        if [[ -f "$binary" ]]; then
            sha256sum "$binary" >> SHA256SUMS
        fi
    done
    echo -e "${GREEN}  Checksums written to SHA256SUMS${NC}"
    popd
}

# Build for a single architecture
build_single_arch() {
    local target=$1
    local arch=$2
    local tag=$3
    
    echo -e "${BWHITE}Building for: ${VIOLET}OS=${target}, ${TOMATO}ARCH=${arch}${NC}"
    
    start_timer "total_build_${arch}"

    # Ensure we are in the project root
    local script_dir="${0%/*}"
    pushd "$script_dir"

    # Load version info
    version_file="./version${tag:+-$tag}.sh"
    if [[ ! -f "$version_file" ]]; then
        echo -e "${RED}ERROR: Version file not found: $version_file${NC}" >&2
        return 1
    fi

    # shellcheck source=version.sh
    source "$version_file"

    # Validate required variables
    if [[ -z ${bash_version:-} ]]; then
        echo -e "${RED}ERROR: bash_version not set in $version_file${NC}" >&2
        return 1
    fi

    # Make build directory
    mkdir -p build && pushd build

    # Prepare GPG for verification (skip if NOSIG is set)
    if [[ ! ${NOSIG:-} ]]; then
        start_timer "gpg_setup"
        echo -e "${LEMON}= Preparing GPG${NC}"
        export GNUPGHOME=${PWD}/.gnupg
        mkdir -p "$GNUPGHOME"
        chmod 700 "$GNUPGHOME"

        # Import public keys
        import_gpg_key 7C0135FB088AAF6C66C650B9BB5869F064EA74AB || return 2  # bash
        import_gpg_key 836489290BB6B70F99FFDA0556BCDB593020450F || return 2  # musl
        end_timer "gpg_setup"
    else
        echo -e "${YELLOW}WARNING: Skipping GPG setup (NOSIG is set)${NC}" >&2
    fi

    # Download bash tarball
    start_timer "download_bash"
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
        return 1
    fi
    end_timer "download_bash"

    # Extract bash
    start_timer "extract_bash"
    echo -e "${HOTPINK}= Extracting bash ${bash_version}${NC}"
    rm -rf bash-"${bash_version}"
    
    if [[ -n ${PARALLEL_EXTRACT:-} ]] && command -v pigz >/dev/null 2>&1; then
        pigz -dc "bash-${bash_version}.tar.gz" | tar -x
    else
        tar -xzf "bash-${bash_version}.tar.gz"
    fi
    end_timer "extract_bash"

    # Apply official patches
    start_timer "patch_bash"
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

    echo -e "\n"

    # Apply custom bash patches
    apply_patches_parallel "$ROOTDIR/custom/bash" "bash-${bash_version}" "bash${bash_version/\./}*.patch"
    echo -e "\n"
    end_timer "patch_bash"

    # Configure arguments
    configure_args=(--enable-silent-rules)
    host_arg=""

    # Platform-specific setup
    if [[ $target == linux ]]; then
        start_timer "setup_toolchain"
        if . /etc/os-release 2>/dev/null && [[ ${ID:-} == alpine ]]; then
            echo -e "${BWHITE}= Skipping installation of musl (already installed on Alpine)${NC}"
        elif [[ ${DL_TOOLCHAIN:-} ]]; then
            # Try to use prebuilt toolchain
            if setup_musl_toolchain "$arch"; then
                echo -e "${GREEN}= Successfully configured musl toolchain${NC}"

                # Set host argument for cross-compilation
                host_arg="--host=$(get_musl_toolchain "$arch")"

                # Add -std=gnu17 for musl toolchain compatibility
                export CFLAGS="-std=gnu17 ${CFLAGS:-}"
            else
                # Fallback to building musl if toolchain download fails
                build_musl_from_source
            fi
        else
            build_musl_from_source
        fi
        end_timer "setup_toolchain"

        # Linux-specific flags
        export CFLAGS="${CFLAGS:-} -Os -static -ffunction-sections -fdata-sections"
        export LDFLAGS="${LDFLAGS:-} -Wl,--gc-sections"
        
        # Add LTO if requested
        if [[ -n ${USE_LTO:-} ]]; then
            export CFLAGS="${CFLAGS} -flto"
            export LDFLAGS="${LDFLAGS} -flto"
            echo -e "${CANARY}= LTO enabled${NC}"
        fi

        # Add architecture-specific CFLAGS
        arch_cflags=$(get_arch_cflags "$arch")
        [[ -n $arch_cflags ]] && export CFLAGS="${CFLAGS} ${arch_cflags}"
        
        # Add aggressive optimizations if requested
        if [[ -n ${AGGRESSIVE_OPT:-} ]]; then
            export CFLAGS="${CFLAGS} -O3 -ffast-math -funroll-loops"
            echo -e "${CANARY}= Aggressive optimizations enabled${NC}"
        fi

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
                export CFLAGS="-Os -target arm64-apple-macos11 -arch arm64"
                export CXXFLAGS="${CFLAGS}"
                export LDFLAGS="${CFLAGS}"
                host_arg="--host=aarch64-apple-darwin"
                # Add custom CFLAGS if provided
                [[ -n ${EXTRA_CFLAGS:-} ]] && export CFLAGS="${CFLAGS} ${EXTRA_CFLAGS}"
            # If $arch is x86_64 for mac, target Intel mac
            elif [[ $arch == x86_64 ]]; then
                export CFLAGS="-Os -target x86_64-apple-macos10.12 -mmacosx-version-min=10.12 -arch x86_64"
                export CXXFLAGS="${CFLAGS}"
                export LDFLAGS="${CFLAGS}"
                host_arg="--host=x86_64-apple-macos10.12"
                # Add custom CFLAGS if provided
                [[ -n ${EXTRA_CFLAGS:-} ]] && export CFLAGS="${CFLAGS} ${EXTRA_CFLAGS}"
            fi
        fi
    fi

    # mipsel will NOT compile on Github Actions without this
    if [[ $arch == mipsel ]]; then
       host_arg="--host=mipsel-unknown-linux-muslsf"
    fi
    
    # Setup ccache if available
    setup_ccache || true

    echo -e "${BLUE}===========${REBECCA} Configuration: ${BLUE}=============${NC}"
    echo -e "${TEAL}= Building bash ${bash_version}${NC}"
    echo -e "${LIGHTROYAL}  CFLAGS: ${CFLAGS:-none}${NC}"
    echo -e "${TURQUOISE}  LDFLAGS: ${LDFLAGS:-none}${NC}"
    echo -e "${MINT}  Host: ${host_arg:-native}${NC}"
    [[ -f "$STRIPCMD" ]] && echo -e "${SKY}  strip: $STRIPCMD${NC}"
    [[ -n ${WITH_TESTS:-} ]] && echo -e " ${BWHITE} Build Tests: ${PINK}yes${NC}" || echo -e " ${BWHITE} Build Tests: ${LIME}no${NC}"
    [[ -n ${USE_CCACHE:-} ]] && echo -e " ${BWHITE} ccache: ${GREEN}enabled${NC}"
    [[ -n ${USE_LTO:-} ]] && echo -e " ${BWHITE} LTO: ${GREEN}enabled${NC}"
    echo -e "${BLUE}========================================${NC}"

    pushd bash-"${bash_version}"

    start_timer "configure"
    export CPPFLAGS="${CFLAGS}" # Some versions need both set
    autoconf -f && ./configure --without-bash-malloc "${configure_args[@]}" "${host_arg}"
    end_timer "configure"

    # Parallel build based on platform
    start_timer "compile"
    make -j"$(get_parallel_jobs)" -s
    end_timer "compile"
    
    if [[ -n ${WITH_TESTS:-} ]]; then
        start_timer "tests"
        make -j"$(get_parallel_jobs)" -s tests
        end_timer "tests"
    fi

    popd # bash-${bash_version}
    popd # build

    echo -e "${PURPLE}= Extracting bash ${bash_version} binary${NC}"
    mkdir -p releases
    cp build/bash-"${bash_version}"/bash releases/bash-"${bash_version}"-"${arch}"

    # Strip binary based on architecture and platform
    start_timer "strip"
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
    end_timer "strip"

    # Clean up build directory unless KEEP_BUILD is set
    if [[ ! ${KEEP_BUILD:-} ]]; then
        echo -e "${HELIOTROPE}Cleaning up build directory${NC}"
        rm -rf build/bash-"${bash_version}"
    fi

    # Compress with UPX (skip on macOS or if disabled)
    if [[ ! ${NO_UPX:-} ]] && [[ "$target" != "macos" ]] && command -v upx >/dev/null 2>&1; then
        start_timer "upx"
        echo -e "${ORANGE}= Compressing with UPX${NC}"
        upx --ultra-brute releases/bash-"${bash_version}"-"${arch}" 2>/dev/null || true
        end_timer "upx"
    elif [[ "$target" == "macos" ]]; then
        echo -e "${PLUM}= Skipping UPX compression on macOS (currently unsupported)${NC}"
    elif [[ ${NO_UPX:-} ]]; then
        echo -e "${PINK}= Skipping UPX compression (disabled)${NC}"
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

    end_timer "total_build_${arch}"
    
    # Show timing summary if profiling
    if [[ -n ${PROFILE_BUILD:-} ]]; then
        echo -e "\n${SLATE}=== Build Timing Summary ===${NC}"
        for key in "${!BUILD_TIMINGS[@]}"; do
            echo -e "${SLATE}  $key${NC}"
        done
    fi

    echo -e "${GREEN}= Done ${NC}"
    echo -e "${LEMON}Build completed successfully!${NC}"

    popd # project root
    
    return 0
}

main() {
    parsed_args=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help|help)
                usage
                exit 0
                ;;
            --dl-toolchain)
                export DL_TOOLCHAIN=1
                shift
                ;;
            --nosig)
                NOSIG=1
                shift
                ;;
            --extra-cflags)
                EXTRA_CFLAGS=${2:-}
                [[ -z ${EXTRA_CFLAGS} ]] && { echo -e "${RED}ERROR: --extra-cflags requires a value${NC}" >&2; exit 1; }
                shift 2
                ;;
            --extra-cflags=*)
                EXTRA_CFLAGS=${1#*=}
                shift
                ;;
            --with-tests)
                WITH_TESTS=1
                shift
                ;;
            --keep-build)
                KEEP_BUILD=1
                shift
                ;;
            --njobs)
                NJOBS=${2:-}
                [[ -z ${NJOBS} ]] && { echo -e "${RED}ERROR: --njobs requires a value${NC}" >&2; exit 1; }
                shift 2
                ;;
            --njobs=*)
                NJOBS=${1#*=}
                shift
                ;;
            --no-upx)
                NO_UPX=1
                shift
                ;;
            --ccache)
                USE_CCACHE=1
                shift
                ;;
            --lto)
                USE_LTO=1
                shift
                ;;
            --aggressive)
                AGGRESSIVE_OPT=1
                shift
                ;;
            --cache-dir)
                CACHE_DIR=${2:-}
                [[ -z ${CACHE_DIR} ]] && { echo -e "${RED}ERROR: --cache-dir requires a value${NC}" >&2; exit 1; }
                shift 2
                ;;
            --cache-dir=*)
                CACHE_DIR=${1#*=}
                shift
                ;;
            --parallel-extract)
                PARALLEL_EXTRACT=1
                shift
                ;;
            --batch)
                BATCH_ARCHS=${2:-}
                [[ -z ${BATCH_ARCHS} ]] && { echo -e "${RED}ERROR: --batch requires a value${NC}" >&2; exit 1; }
                shift 2
                ;;
            --batch=*)
                BATCH_ARCHS=${1#*=}
                shift
                ;;
            --checksum)
                GEN_CHECKSUM=1
                shift
                ;;
            --profile)
                PROFILE_BUILD=1
                shift
                ;;
            --)
                shift
                # Add all remaining args to parsed_args
                parsed_args+=("$@")
                break
                ;;
            --*)
                # Unknown long option
                echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
                echo -e "${YELLOW}Use --help to see available options${NC}" >&2
                exit 1
                ;;
            -*)
                # Unknown short option
                echo -e "${RED}ERROR: Unknown option: $1${NC}" >&2
                echo -e "${YELLOW}Use --help to see available options${NC}" >&2
                exit 1
                ;;
            *)
                # This is a positional argument
                parsed_args+=("$1")
                shift
                ;;
        esac
    done

    # Handle clean command
    if [[ ${parsed_args[0]:-} = 'clean' ]]; then
        rm -fr build/ releases/ .cache/ .ccache/
        echo -e "${ORANGE}Cleaned build/, releases/, .cache/, and .ccache/!${NC}"
        exit 0
    fi

    myT=$(uname -s) && dO=$(echo "$myT" | tr '[:upper:]' '[:lower:]')
    myA=$(uname -m) && dA=$(echo "$myA" | tr '[:upper:]' '[:lower:]')

    # Extract positional arguments (OS, ARCH, TAG) from parsed_args
    local target=$dO
    local default_arch=$dA
    local tag=""
    
    # Process positional arguments
    if [[ ${#parsed_args[@]} -ge 1 ]]; then
        target=${parsed_args[0]}
    fi
    if [[ ${#parsed_args[@]} -ge 2 ]] && [[ -z ${BATCH_ARCHS:-} ]]; then
        # Only use positional arch if NOT in batch mode
        default_arch=$(normalize_arch "${parsed_args[1]}")
    fi
    if [[ ${#parsed_args[@]} -ge 3 ]] && [[ -z ${BATCH_ARCHS:-} ]]; then
        tag=${parsed_args[2]}
    elif [[ ${#parsed_args[@]} -ge 2 ]] && [[ -n ${BATCH_ARCHS:-} ]]; then
        # In batch mode, second arg is tag
        tag=${parsed_args[1]}
    fi
    
    declare -r musl_mirror='https://musl.libc.org/releases'

    # Handle batch builds
    if [[ -n ${BATCH_ARCHS:-} ]]; then
        echo -e "${GOLD}=== Batch Build Mode ===${NC}"
        echo -e "${BWHITE}Target OS: ${target}${NC}"
        IFS=',' read -ra archs <<< "$BATCH_ARCHS"
        
        local failed_builds=()
        local successful_builds=()
        
        for arch in "${archs[@]}"; do
            arch=$(normalize_arch "$arch")
            echo -e "\n${VIOLET}=== Building for ${arch} ===${NC}\n"
            
            if build_single_arch "$target" "$arch" "$tag"; then
                successful_builds+=("$arch")
            else
                failed_builds+=("$arch")
                echo -e "${RED}Build failed for ${arch}${NC}"
            fi
        done
        
        # Summary
        echo -e "\n${GOLD}=== Batch Build Summary ===${NC}"
        echo -e "${GREEN}Successful: ${#successful_builds[@]} architectures${NC}"
        for arch in "${successful_builds[@]}"; do
            echo -e "  ${GREEN}✓${NC} $arch"
        done
        
        if [[ ${#failed_builds[@]} -gt 0 ]]; then
            echo -e "${RED}Failed: ${#failed_builds[@]} architectures${NC}"
            for arch in "${failed_builds[@]}"; do
                echo -e "  ${RED}✗${NC} $arch"
            done
        fi
        
        # Generate checksums if requested
        if [[ -n ${GEN_CHECKSUM:-} ]]; then
            generate_checksums "releases"
        fi
        
        exit 0
    fi

    # Single architecture build
    build_single_arch "$target" "$default_arch" "$tag"
    
    # Generate checksums if requested
    if [[ -n ${GEN_CHECKSUM:-} ]]; then
        generate_checksums "releases"
    fi
}

# Only execute if not being sourced
if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    main "$@"
fi
