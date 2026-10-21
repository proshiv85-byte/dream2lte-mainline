#!/bin/sh
# Fetch mainline Linux at the base commit of the patches and apply them.
set -e
cd "$(dirname "$0")/.."
BASE=$(cat patches/BASE)
git init -q linux
git -C linux fetch --depth 1 https://github.com/torvalds/linux.git "$BASE"
git -C linux checkout -q -b dream2lte FETCH_HEAD
git -C linux am -q ../patches/*.patch
git -C linux log --oneline | head -n 20
