#!/bin/sh
# tools/phone-sysroot.sh DIR: copy the phone's libraries and headers to DIR,
# for cross-compiling against exactly what is installed there (FFmpeg,
# Mesa). The cross linker has no sysroot support, so linker scripts get
# relative paths. Does nothing if DIR already has them.
set -e
D=$1
PH=${PH:-ssh root@172.16.42.1}
[ -n "$D" ] || { echo "usage: $0 DIR" >&2; exit 1; }
[ -d "$D/usr/lib" ] && exit 0
mkdir -p "$D"
echo "copying the phone's /usr/include and /usr/lib to $D"
$PH 'tar -C / -cf - --exclude=usr/lib/firefox --exclude="usr/lib/python3*" \
	--exclude=usr/lib/modules --exclude=usr/lib/firmware --exclude=usr/lib/gcc \
	--exclude="usr/lib/libLLVM*" --exclude="usr/lib/libgallium*" \
	usr/include usr/lib usr/share/pkgconfig usr/share/wayland-protocols \
	usr/share/wayland 2>/dev/null' | tar -C "$D" -xf -
ln -sfn usr/lib "$D/lib"; ln -sfn usr/lib "$D/lib64"; ln -sfn lib "$D/usr/lib64"
for f in $(grep -l "GROUP\|INPUT" $(find "$D/usr/lib" -maxdepth 1 -name "*.so" -size -4k -type f)); do
	sed -i -E 's#(/usr)?/lib(64)?/##g' "$f"
done
