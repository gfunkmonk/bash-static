#!/usr/bin/env bash
# generate changelog text

set -eo pipefail

# read version information
. ./version.sh

# output release notes to NOTES.txt
printf 'bash %s-%03d, with musl %s\n' \
    "${bash_version}" "${bash_patch_level}" "${musl_version}" > NOTES.txt
