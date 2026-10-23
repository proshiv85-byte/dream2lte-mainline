#!/bin/sh
# Rebuild the phone's libavcodec with V4L2 DRM-PRIME output, so that Firefox
# can use the hardware video decoder (MFC). Cross-compiled on the PC against
# a copy of the phone's /usr, with the configure options of the phone's own
# FFmpeg; only libavcodec is replaced on the phone (backup kept in
# /root/mainline/ffmpeg-orig).
#
#   PH="ssh root@172.16.42.1" tools/ffmpeg-v4l2/build.sh [install]
#
# Patches: LibreELEC's v4l2-drmprime series (DRM-PRIME frames from the
# v4l2m2m decoders) and a fix to keep timestamps when the caller sets no
# time base (Firefox). Re-run after an FFmpeg update on the phone.
set -e
T=$(cd "$(dirname "$0")" && pwd)
W=${WORK:-$T/../../out/ffmpeg-v4l2}
PH=${PH:-ssh root@172.16.42.1}
mkdir -p "$W" && cd "$W"

# version and configure options of the phone's FFmpeg
$PH 'ffmpeg -hide_banner -buildconf' > buildconf.txt 2>&1
V=$($PH "pacman -Q ffmpeg" | sed 's/.*:\([0-9.]*\)-.*/\1/')
echo "phone FFmpeg $V"

# sysroot: the phone's libraries and headers. The cross linker has no
# sysroot support, so linker scripts get relative paths.
if [ ! -d sysroot/usr/lib ]; then
	mkdir -p sysroot
	$PH 'tar -C / -cf - --exclude=usr/lib/firefox --exclude="usr/lib/python3*" \
		--exclude=usr/lib/modules --exclude=usr/lib/firmware --exclude=usr/lib/gcc \
		--exclude="usr/lib/libLLVM*" --exclude="usr/lib/libgallium*" \
		usr/include usr/lib usr/share/pkgconfig 2>/dev/null' | tar -C sysroot -xf -
	ln -sfn usr/lib sysroot/lib; ln -sfn usr/lib sysroot/lib64; ln -sfn lib sysroot/usr/lib64
	for f in $(grep -l "GROUP\|INPUT" $(find sysroot/usr/lib -maxdepth 1 -name "*.so" -size -4k -type f)); do
		sed -i -E 's#(/usr)?/lib(64)?/##g' "$f"
	done
fi

# source with the patches
if [ ! -d ffmpeg-$V ]; then
	curl -fL https://ffmpeg.org/releases/ffmpeg-$V.tar.xz | tar -xJf -
	(cd ffmpeg-$V && for p in "$T"/patches/*.patch; do patch -p1 < "$p"; done)
fi

# options whose build dependencies are not on the phone; none of them
# changes libavcodec on this hardware
DROP="--enable-avisynth|--enable-frei0r|--enable-ladspa|--enable-opencl|--enable-vapoursynth|--enable-amf"
OPTS=$(sed -n '3,$p' buildconf.txt | grep -- '--' | grep -vxE "\s*($DROP)\s*" | tr -s ' \n' ' ')
S=$W/sysroot
export PKG_CONFIG_LIBDIR=$S/usr/lib/pkgconfig:$S/usr/share/pkgconfig PKG_CONFIG_SYSROOT_DIR=$S
mkdir -p build && cd build
[ -f config.h ] || ../ffmpeg-$V/configure $OPTS --enable-cross-compile --arch=aarch64 \
	--target-os=linux --cross-prefix=aarch64-linux-gnu- --sysroot=$S --pkg-config=pkg-config \
	--extra-ldflags="-L$S/usr/lib -Wl,-rpath-link,$S/usr/lib" > ../configure.log
make -j$(nproc) > ../make.log

# same exports as the phone's libavcodec, or don't touch it
L=$(cd "$S/usr/lib" && ls libavcodec.so.*.*.*)
aarch64-linux-gnu-nm -D --defined-only "$S/usr/lib/$L" | awk '{print $3}' | sort > ../old.sym
aarch64-linux-gnu-nm -D --defined-only libavcodec/libavcodec.so.* | awk '{print $3}' | sort -u > ../new.sym
cmp -s ../old.sym ../new.sym || { echo "exported symbols differ from the phone's $L" >&2; exit 1; }
echo "built libavcodec ($L), exports match"

[ "$1" = install ] || exit 0
$PH "mkdir -p /root/mainline/ffmpeg-orig; [ -f /root/mainline/ffmpeg-orig/$L ] || cp -a /usr/lib/$L /root/mainline/ffmpeg-orig/; cat > /tmp/$L.new" < "libavcodec/$(readlink libavcodec/libavcodec.so)"
$PH "install -m755 /tmp/$L.new /usr/lib/$L && rm /tmp/$L.new && echo installed /usr/lib/$L"
