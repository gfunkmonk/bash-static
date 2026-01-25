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
__USAGE
}

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

# Silence pushd/popd
pushd() { command pushd "$@" >/dev/null; }
popd() { command popd >/dev/null; }

# Only pull files that don't already exist
mycurl() {
    (($# == 2)) || return 1
    local url=$1
    local sig_ext=$2
    local filename=${url##*/}

    if [[ ! -f ${filename} ]]; then
        echo -e "${HELIOTROPE}Downloading: ${filename}${NC}"
        echo "  URL: ${url}"
        curl -sSfLO "$url" || return 1
    else
        echo -e "${BWHITE}Using cached: ${filename}${NC}"
    fi

    if [[ ! ${NO_SIGS:-} ]]; then
        if [[ ! -f ${filename}.${sig_ext} ]]; then
            echo -e "${HELIOTROPE}Downloading signature: ${filename}.${sig_ext}${NC}"
            echo "  URL: ${url}.${sig_ext}"
            curl -sSfLO "${url}.${sig_ext}" || return 1
        fi
        echo "Verifying signature: ${filename}"
        gpg --trust-model always --verify "${filename}.${sig_ext}" "${filename}" 2>/dev/null || {
            echo "ERROR: GPG verification failed for ${filename}" >&2
            return 1
        }
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
        echo "GPG key ${key} already imported"
        return 0
    fi

    echo "Importing GPG key: ${key}"
    for i in {1..3}; do
        for server in "${keyservers[@]}"; do
            if gpg --quiet --keyserver "$server" --recv-keys "$key" 2>/dev/null; then
                echo "Successfully imported key from $server"
                return 0
            fi
        done
        [[ $i -lt 3 ]] && sleep 5
    done

    echo "ERROR: Failed to import GPG key ${key}" >&2
    return 1
}

# Normalize architecture names
normalize_arch() {
    local raw_arch=$1
    case "$raw_arch" in
        arm64) echo "aarch64" ;;
        armv7l) echo "armv7" ;;
        armv6l) echo "armv6" ;;
        x86-64|amd64) echo "x86_64" ;;
        i686|i586) echo "i386" ;;
        *) echo "$raw_arch" ;;
    esac
}

# Get per-architecture default CFLAGS
get_arch_cflags() {
    local arch=$1
    case "$arch" in
        aarch64) echo "-march=armv8-a" ;;
        armv7) echo "-march=armv7-a -mfpu=neon-vfpv4 -mfloat-abi=hard" ;;
        armv6) echo "-march=armv6 -mfloat-abi=hard -mfpu=vfp" ;;
        x86_64) echo "-march=x86-64 -mtune=generic" ;;
        i386) echo "-march=i686 -mtune=generic" ;;
        riscv64) echo "-march=rv64gc -mabi=lp64d" ;;
        *) echo "" ;;
    esac
}

main() {
  [[ ${1} = '-h' || ${1} = '--help' ]] && usage && exit 0

  myT=$(uname -s) && dO=$(echo "$myT" | tr '[:upper:]' '[:lower:]')
  myA=$(uname -m) && dA=$(echo "$myA" | tr '[:upper:]' '[:lower:]')

  declare -r target=${1:-$dO}
  declare -r arch=$(normalize_arch "${2:-$dA}")
  declare -r tag=${3:-}

  echo -e "${VIOLET}Building for: OS=${target}, ARCH=${arch}${NC}"

  #declare -r bash_mirror='https://ftp.gnu.org/gnu/bash'
  declare -r musl_mirror='https://musl.libc.org/releases'

  # Ensure we are in the project root
  pushd "${0%/*}"

  # Load version info
  version_file="./version${tag:+-$tag}.sh"
  if [[ ! -f "$version_file" ]]; then
      echo "ERROR: Version file not found: $version_file" >&2
      exit 1
  fi
  # shellcheck source=version.sh
  source "$version_file"

  # Validate required variables
  if [[ -z ${bash_version:-} ]]; then
      echo "ERROR: bash_version not set in $version_file" >&2
      exit 1
  fi

  # make build directory
  mkdir -p build && pushd build

  # Prepare GPG for verification
  echo -e "${HOTPINK}= Preparing GPG${NC}"
  export GNUPGHOME=${PWD}/.gnupg
  mkdir -p "$GNUPGHOME"
  chmod 700 "$GNUPGHOME"

  # Import public keys
  import_gpg_key 7C0135FB088AAF6C66C650B9BB5869F064EA74AB || exit 2  # bash
  import_gpg_key 836489290BB6B70F99FFDA0556BCDB593020450F || exit 2  # musl

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
      echo -e "${RED}Failed to download from $mirror, trying next...${NC}"
  done

  if [[ $bash_downloaded == false ]]; then
      echo -e "${RED}ERROR: Failed to download bash from all mirrors${NC}" >&2
      exit 1
  fi

  # Extract bash
  echo -e "${LEMON}= Extracting bash ${bash_version}${NC}"
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
            echo -e "${RED}Failed to download patch from $mirror, trying next...${NC}"
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
  echo -e "${BLUE}= Applying custom patches${NC}"
  for patch in ../custom/bash"${bash_version/\./}"*.patch; do
        if [[ -f "$patch" ]]; then
            echo "Applying ${patch##*/}"
            pushd bash-"${bash_version}"
            patch -sp1 <../"${patch}" || {
                echo "WARNING: Failed to apply custom patch ${patch##*/}" >&2
            }
            popd
        fi
  done

  # Configure arguments
  configure_args=(--enable-silent-rules)
  host_arg=""

  # Platform-specific setup
  if [[ $target == linux ]]; then
    if . /etc/os-release && [[ $ID == alpine ]]; then
      echo "${BWHITE}= skipping installation of musl (already installed on Alpine)${NC}"
    else
      install_dir=${PWD}/musl-install-${musl_version}
      if [[ -f ${install_dir}/bin/musl-gcc ]]; then
        echo -e "${LAGOON}= reusing existing musl ${musl_version}${NC}"
      else
        echo -e "${CANARY}= downloading musl ${musl_version}${NC}"
        mycurl ${musl_mirror}/musl-"${musl_version}".tar.gz asc

        echo -e "${KHAKI}= extracting musl ${musl_version}${NC}"
        rm -rf musl-"${musl_version}"
        tar -xf musl-"${musl_version}".tar.gz

        echo -e "${CORAL}= building musl ${musl_version}${NC}"
        pushd musl-"${musl_version}"
        ./configure --prefix="${install_dir}" "${configure_args[@]}"
        make -j"$(nproc)" -s install
        popd # musl-${musl-version}
        rm -rf musl-"${musl_version}"
      fi

      echo -e "${BWHITE}= setting CC to musl-gcc ${musl_version}${NC}"
      export CC=${install_dir}/bin/musl-gcc
    fi
        
    # Linux-specific flags
    export CFLAGS="${CFLAGS:-} -Os -static -ffunction-sections -fdata-sections"
    export LDFLAGS="${LDFLAGS:-} -Wl,--gc-sections"

    # Add architecture-specific CFLAGS
    arch_cflags=$(get_arch_cflags "$arch")
    [[ -n $arch_cflags ]] && export CFLAGS="${CFLAGS} ${arch_cflags}"

  else
    echo -e "${BROWN}= WARNING: your platform does not support static binaries.${NC}"
    echo -e "${BROWN}= (This is mainly due to non-static libc availability.)${NC}"

    if [[ $target == macos ]]; then
      # set minimum version of macOS to 10.13
      export MACOSX_DEPLOYMENT_TARGET="10.13"
      export MACOS_TARGET="10.13"
      export CC="clang -std=c89 -Wno-return-type -Wno-implicit-function-declaration"
      export CXX="clang -std=c89 -Wno-return-type -Wno-implicit-function-declaration"
      # use included gettext to avoid reading from other places, like homebrew
      configure_args=("${configure_args[@]}" "--with-included-gettext")

      # if $arch is aarch64 for mac, target arm64
      if [[ $arch == aarch64 ]]; then
        export CFLAGS="-Os -target arm64-apple-macos"
        host_arg="--host=aarch64-apple-darwin"
        #configure_args=("${configure_args[@]}" "--host=aarch64-apple-darwin")
      #else
      #  export CFLAGS="${CFLAGS:-} -Os -target x86_64-apple-macos10.12"
      #  configure_args=("${configure_args[@]}" "--host=x86_64-apple-macos10.12")
      fi
    fi
  fi

  if [[ "$arch" = "mipsel" ]]; then
      host_arg="--host=mipsel-linux-musl"
  fi

  echo -e "${TEAL}= building bash ${bash_version}${NC}"
  pushd bash-"${bash_version}"
  export CPPFLAGS="${CFLAGS}" # Some versions need both set
  autoconf -f && ./configure --without-bash-malloc "${configure_args[@]}" "${host_arg}"
  #make -s && make -s tests
  if [ "$target" != "macos" ]; then
    make -j"$(nproc)" -s
  else
    make -j"$(sysctl -n hw.physicalcpu)"
  fi
  popd # bash-${bash_version}
  popd # build

  echo -e "${PURPLE}= extracting bash ${bash_version} binary${NC}"
  mkdir -p releases
  cp build/bash-"${bash_version}"/bash releases/bash-"${bash_version}"-static

  # Strip binary based on architecture and platform
  if [ "$arch" = "mipsel" ]; then
    echo -e "${LIME}= Stripping binary (mipsel)${NC}"
    mipsel-linux-muslsf-strip -s releases/bash-"${bash_version}"-static || true
  elif [ "$target" != "macos" ]; then
    echo -e "${LIME}= Stripping binary${NC}"
    strip -s releases/bash-"${bash_version}"-static || true
  else
    echo -e "${LIME}= Stripping binary (macOS)${NC}"
    strip -S releases/bash-"${bash_version}"-static || true
  fi

  rm -rf build/bash-"${bash_version}"

  # Compress with UPX (skip on macOS)
  if [ "$target" != "macos" ]; then
    if command -v upx >/dev/null 2>&1; then
      echo -e "${ORANGE}= compressing${NC}"
      upx --ultra-brute releases/bash-"${bash_version}"-static 2>/dev/null || true
    else
      echo -e "${PINK}= Skipping UPX compression (not installed)${NC}"
    fi
  fi

  # Display results
  echo ""
  echo -e "${NAVAJO}= Build complete!${NC}"
  echo -e "${PEACH}  Output: releases/bash-${bash_version}-static${NC}"
  echo -e "${JUNEBUD}  Size: $(du -h releases/bash-"${bash_version}"-static 2>/dev/null | cut -f1 || echo 'unknown')${NC}"

  # Show binary info
  if command -v file >/dev/null 2>&1; then
    echo -e "${ORCHID}  Type: $(file releases/bash-"${bash_version}"-static)${NC}"
  fi

  echo -e "${GREEN}= done${NC}"

  popd # project root
}

# Only execute if not being sourced
[[ ${BASH_SOURCE[0]} == "$0" ]] || return 0 && main "$@"