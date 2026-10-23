#!/bin/sh
# Build Mesa (panfrost only) with the Mali-G71 derivative fix and install it
# to /opt/mesa-g71 on the phone; armtix-sway uses it when it is there.
#
#   PH="ssh root@172.16.42.1" tools/mesa-g71/build.sh [install]
#
# On G71, panfrost's derivatives (dFdx/dFdy/fwidth) returned +/- the value
# itself, so fwidth()-based antialiasing (Firefox's rounded clips, GTK4)
# drew half transparent blocks. With the patch they are zero on G71 (hard
# edges, correct shapes). Needs on the PC: meson, ninja, clang, llvm, libclc,
# spirv-llvm-translator (to build Mesa's CL kernel compilers natively) and an
# aarch64-linux-gnu cross toolchain. The phone's libraries come from the
# sysroot of tools/ffmpeg-v4l2/build.sh (run that first). Re-run after a Mesa
# update on the phone.
set -e
T=$(cd "$(dirname "$0")" && pwd)
W=${WORK:-$T/../../out/mesa-g71}
S=${SYSROOT:-$T/../../out/ffmpeg-v4l2/sysroot}
PH=${PH:-ssh root@172.16.42.1}
[ -d "$S/usr/lib" ] || { echo "no sysroot in $S, run tools/ffmpeg-v4l2/build.sh first" >&2; exit 1; }
S=$(cd "$S" && pwd)
mkdir -p "$W" && cd "$W"

V=$($PH "pacman -Q mesa" | sed 's/.*:\([0-9.]*\)-.*/\1/')
echo "phone Mesa $V"
[ -d "$S/usr/share/wayland-protocols" ] ||
	$PH 'tar -C / -cf - usr/share/wayland-protocols usr/share/wayland' | tar -C "$S" -xf -

if [ ! -d mesa-$V ]; then
	curl -fL https://archive.mesa3d.org/mesa-$V.tar.xz | tar -xJf -
	(cd mesa-$V && patch -p1 < "$T"/0001-pan-bi-fix-derivatives-on-Mali-G71.patch)
fi

# mako for Mesa's code generators, without touching the system Python
[ -x venv/bin/python ] || { python3 -m venv --system-site-packages venv && venv/bin/pip install -q mako pyyaml; }
export PATH=$W/native-install/bin:$W/venv/bin:$PATH

# build-time tools: Mesa's CL compiler and panfrost's kernel precompiler
if [ ! -x native-install/bin/panfrost_compile ]; then
	meson setup native mesa-$V --prefix="$W/native-install" --buildtype=release \
		-Dplatforms= -Dgallium-drivers=panfrost -Dvulkan-drivers= -Degl=disabled \
		-Dgbm=disabled -Dglx=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
		-Dglvnd=disabled -Dllvm=enabled -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
		-Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true -Dvideo-codecs= \
		-Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false \
		-Dgallium-va=disabled -Dgallium-rusticl=false -Dtools= > native-setup.log
	ninja -C native install > native-build.log
fi

cat > cross.ini <<EOF
[binaries]
c = 'aarch64-linux-gnu-gcc'
cpp = 'aarch64-linux-gnu-g++'
ar = 'aarch64-linux-gnu-ar'
strip = 'aarch64-linux-gnu-strip'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-isystem', '$S/usr/include']
cpp_args = ['-idirafter', '$S/usr/include']
c_link_args = ['-L$S/usr/lib', '-Wl,-rpath-link,$S/usr/lib']
cpp_link_args = ['-L$S/usr/lib', '-Wl,-rpath-link,$S/usr/lib']

[properties]
sys_root = '$S'
pkg_config_libdir = '$S/usr/lib/pkgconfig:$S/usr/share/pkgconfig'
needs_exe_wrapper = true

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF
[ -f build/build.ninja ] || meson setup build mesa-$V --cross-file cross.ini \
	--prefix=/opt/mesa-g71 --libdir=lib --buildtype=release -Db_ndebug=true \
	-Dplatforms=wayland -Dgallium-drivers=panfrost -Dvulkan-drivers= -Degl=enabled \
	-Dgbm=enabled -Dglx=disabled -Dgles1=disabled -Dgles2=enabled -Dopengl=true \
	-Dglvnd=enabled -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
	-Dvideo-codecs= -Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled \
	-Dbuild-tests=false -Dgallium-va=disabled -Dgallium-rusticl=false -Dtools= > setup.log
ninja -C build > build.log
rm -rf stage && DESTDIR=$W/stage ninja -C build install > install.log
J=stage/opt/mesa-g71/share/glvnd/egl_vendor.d/50_mesa.json
sed -i 's#"library_path" : "libEGL_mesa.so.0"#"library_path" : "/opt/mesa-g71/lib/libEGL_mesa.so.0"#' $J
echo "built Mesa $V for /opt/mesa-g71"

[ "$1" = install ] || exit 0
tar -C stage -cf - opt | $PH 'rm -rf /opt/mesa-g71 && tar -C / -xf - && echo installed /opt/mesa-g71'
echo "takes effect when sway is restarted (power menu, Restart desktop)"
