#!/bin/sh
# Export the dream2lte branch of ./linux as patches against its mainline base.
set -e
cd "$(dirname "$0")/.."
BASE=$(cat patches/BASE)
rm -f patches/*.patch
git -C linux format-patch -q --no-signature -o ../patches "$BASE"..dream2lte
ls patches
