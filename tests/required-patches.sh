#!/usr/bin/env bash
# Run with Bash 4+: bash tests/required-patches.sh
# Offline unit tests: real patch/tar, simulated download and compiler boundaries.
set -eo pipefail

fail() { echo "FAIL: $*" >&2; exit 1; }

if [[ ${1:-} == --case ]]; then
    kind=$2 repo=$3 dir=$4 mode=$5 scenario=$6
    cd "$repo"
    source ./build.sh
    cd "$dir"
    case $kind in
        patch)
            mycurl() {
                [[ $2 == sig ]] || return 1
                printf '%s\n' "$1" >> requests
                [[ $1 != absent/* ]] || return 1
                cp "fixtures/${1##*/}" .
            }
            trap 'printf "%s\n" "$PWD" > "$dir/exit-directory"' EXIT
            mirrors=(available)
            [[ $scenario != fallback ]] || mirrors=(absent available)
            level=3
            [[ $scenario != zero ]] || level=0
            if [[ $mode == conditional ]]; then
                # This is how batch mode calls the build: errexit is suppressed.
                if apply_official_bash_patches 5.3 "$level" "${mirrors[@]}"; then
                    exit 0
                else
                    exit "$?"
                fi
            fi
            apply_official_bash_patches 5.3 "$level" "${mirrors[@]}"
            ;;
        build)
            ROOTDIR="$dir/project"
            export NOSIG=1
            unset PARALLEL_EXTRACT PROFILE_BUILD
            mycurl() {
                [[ $1 == */bash-5.3.tar.gz ]] || return 1
                cp "$dir/source.tar.gz" bash-5.3.tar.gz
            }
            apply_patches_parallel() { fail 'continued past failed official patches'; }
            before=$(dirs -p)
            if build_single_arch macos aarch64 53; then
                fail 'build accepted missing patches'
            else
                [[ $? == 1 ]] || fail 'unexpected build status'
            fi
            [[ $(dirs -p) == "$before" ]] || fail 'directory stack changed'
            ;;
        batch)
            build_single_arch() {
                printf '%s\n' "$2" >> attempted
                [[ $scenario != failure || $2 != x86_64 ]]
            }
            unset GEN_CHECKSUM
            main linux x86_64,aarch64 53
            ;;
    esac
    exit 0
fi

[[ ${BASH_VERSINFO[0]} -ge 4 ]] || fail 'Bash 4 or newer is required'
repo=$(cd "$(dirname "$0")/.." && pwd)
script="$repo/tests/required-patches.sh"
root=$(mktemp -d "${TMPDIR:-/tmp}/bash-patch-tests.XXXXXX")
root=$(cd "$root" && pwd)
trap 'echo "Test files: $root"' EXIT

run_case() {
    local expected=$1 kind=$2 dir=$3 mode=$4 scenario=$5 status=0
    "$BASH" "$script" --case "$kind" "$repo" "$dir" "$mode" "$scenario" >"$dir/log" 2>&1 || status=$?
    [[ $status == "$expected" ]] || fail "$kind/$mode/$scenario: expected $expected, got $status (see $dir/log)"
}

for mode in direct conditional; do
    for scenario in success fallback zero missing rejected already-applied; do
        dir="$root/$mode-$scenario"
        mkdir -p "$dir/fixtures" "$dir/bash-5.3"
        printf '0\n' > "$dir/bash-5.3/level"
        [[ $scenario != already-applied ]] || printf '1\n' > "$dir/bash-5.3/level"
        for level in 1 2 3; do
            [[ $scenario != missing || $level != 2 ]] || continue
            before=$((level - 1))
            [[ $scenario != rejected || $level != 2 ]] || before=9
            printf -v name 'bash53-%03d' "$level"
            printf '%s\n' '--- level' '+++ level' '@@ -1 +1 @@' "-$before" "+$level" > "$dir/fixtures/$name"
        done
        case $scenario in
            success|fallback) status=0; expected=3 ;;
            zero) status=0; expected=0 ;;
            *) status=1; expected=1 ;;
        esac
        run_case "$status" patch "$dir" "$mode" "$scenario"
        [[ $(<"$dir/bash-5.3/level") == "$expected" ]] || fail "$mode/$scenario: wrong patch result"
        [[ $(<"$dir/exit-directory") == "$dir" ]] || fail "$mode/$scenario: changed directory"
        if [[ $status != 0 ]]; then
            [[ ! -e "$dir/bash53-003" ]] || fail "$mode/$scenario: acquired later patch after failure"
        fi
        if [[ $scenario == fallback ]]; then
            [[ $(wc -l < "$dir/requests") -eq 6 ]] || fail 'mirror fallback was not exercised'
        fi
        echo "PASS patch: $mode/$scenario"
    done
done

dir="$root/build"
mkdir -p "$dir/project" "$dir/source/bash-5.3"
printf 'fixture\n' > "$dir/source/bash-5.3/level"
printf 'bash_version=5.3\nbash_patch_level=1\n' > "$dir/project/version-53.sh"
tar -czf "$dir/source.tar.gz" -C "$dir/source" bash-5.3
run_case 0 build "$dir" conditional missing
echo 'PASS build: stop before custom patches; restore directory stack'

for scenario in success failure; do
    dir="$root/batch-$scenario"
    mkdir -p "$dir"
    status=0
    [[ $scenario != failure ]] || status=1
    run_case "$status" batch "$dir" conditional "$scenario"
    [[ $(<"$dir/attempted") == $'x86_64\naarch64' ]] || fail 'batch did not attempt both architectures'
    echo "PASS batch: $scenario"
done

rm -rf "$root"
trap - EXIT
