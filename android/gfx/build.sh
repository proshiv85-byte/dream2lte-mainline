#!/bin/bash
# Build the Android graphics stack for the mainline kernel, standalone with
# the NDK (no AOSP tree): Mesa panfrost EGL/GLES, minigbm gralloc0
# (gralloc.minigbm.so) and drm_hwcomposer's HWC2 module (hwcomposer.drm.so).
#
#   android/gfx/build.sh        -> out/android-gfx/stage/lib64/{,egl,hw}
#
# Everything is downloaded and built in out/android-gfx. Needs on the PC:
# curl, git, unzip, meson, ninja, python3, and for Mesa's build-time tools
# what tools/mesa-g71/build.sh needs (clang, llvm, libclc,
# spirv-llvm-translator). The phone links against its own liblog, libcutils,
# libsync, libhardware, libnativewindow, libz: they are pulled from the phone
# (adb, Android or TWRP with SYSTEM/VENDOR mounted) unless out/android-gfx/devlibs
# already has them.
set -e
A=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$A/../.." && pwd)
W=$TOP/out/android-gfx
mkdir -p "$W" && cd "$W"

NDK=android-ndk-r28b
API=34
MESA=26.2.5
LIBDRM=libdrm-2.4.125
MINIGBM=f61c8ce976a26769e951d126e1eeba851133590b
# the last drm_hwcomposer revision with the HWC2 frontend (hwc2_device)
DRMHWC=68a8554bdf3a8d29a3a963b45d995b10512ac5dd
AOSP=https://android.googlesource.com/platform
AOSP_LOGGING=bcac7c30d88a3773a7c0bc9f5617a23a886331fd
AOSP_CORE=a3b721a32242006b59cb12bd62c9133632af3a2d
AOSP_LIBHARDWARE=7e08958a6cbe2b02c9d80a66fba68fd8a864d73d
AOSP_NATIVE=4f463a6b1de9198963dc6aff74154a504ba3f8f6
AOSP_LIBBASE=6d19b5c690fa4220c10e42c2326150bbd4d4b7bb

T=$W/$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin
CC=$T/aarch64-linux-android$API-clang
CXX=$T/aarch64-linux-android$API-clang++
STRIP=$T/llvm-strip
STAGE=$W/stage/lib64

# ---- downloads ----
[ -d $NDK ] || { curl -fL -o ndk.zip https://dl.google.com/android/repository/$NDK-linux.zip &&
	unzip -q ndk.zip && rm ndk.zip; }

gitat() {	# gitat <url> <dir> <commit>
	[ -d "$2" ] || git clone -q "$1" "$2"
	git -C "$2" fetch -q origin "$3" 2>/dev/null || true
	git -C "$2" checkout -q -f "$3"
	git -C "$2" clean -q -fdx
}
gitat https://gitlab.freedesktop.org/mesa/drm.git libdrm $LIBDRM
gitat https://chromium.googlesource.com/chromiumos/platform/minigbm minigbm $MINIGBM
gitat https://gitlab.freedesktop.org/drm-hwcomposer/drm-hwcomposer.git drm-hwc2 $DRMHWC
git -C minigbm apply "$A/minigbm.patch"
git -C drm-hwc2 apply "$A/drm-hwcomposer.patch"

aosp() {	# aosp <repo> <commit> <path in repo> <dir>
	[ -d "aosp-inc/$4" ] && return
	mkdir -p "aosp-inc/$4"
	curl -fsSL "$AOSP/$1/+archive/$2/$3.tar.gz" | tar -xz -C "aosp-inc/$4"
}
aosp system/logging $AOSP_LOGGING liblog/include liblog
aosp system/core $AOSP_CORE libcutils/include libcutils
aosp system/core $AOSP_CORE libsystem/include libsystem
aosp system/core $AOSP_CORE libsync/include libsync
aosp system/core $AOSP_CORE libutils libutils-src
aosp hardware/libhardware $AOSP_LIBHARDWARE include_all libhardware
aosp frameworks/native $AOSP_NATIVE libs/nativewindow/include nativewindow
aosp frameworks/native $AOSP_NATIVE libs/nativebase/include nativebase
aosp system/libbase $AOSP_LIBBASE . libbase

# the phone's libraries to link against (-z defs catches missing symbols)
mkdir -p devlibs
for f in /system/lib64/liblog.so /system/lib64/libsync.so /system/lib64/libnativewindow.so \
	 /vendor/lib64/libcutils.so /vendor/lib64/libhardware.so /vendor/lib64/libz.so; do
	[ -f devlibs/$(basename $f) ] || adb pull $f devlibs/ >/dev/null
done

# ---- libdrm (static) ----
cat > android-aarch64.ini <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$T/llvm-ar'
strip = '$STRIP'
pkg-config = 'pkg-config'

[built-in options]
c_args = ['-fPIC']
cpp_args = ['-fPIC']

[properties]
needs_exe_wrapper = true
pkg_config_libdir = '$W/prefix/lib/pkgconfig'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8-a'
endian = 'little'
EOF
if [ ! -f prefix/lib/libdrm.a ]; then
	meson setup --wipe libdrm-build libdrm --cross-file android-aarch64.ini --prefix=$W/prefix \
		--default-library=static --buildtype=release -Dintel=disabled -Dradeon=disabled \
		-Damdgpu=disabled -Dnouveau=disabled -Dvmwgfx=disabled -Domap=disabled \
		-Dexynos=enabled -Dfreedreno=disabled -Dtegra=disabled -Dvc4=disabled \
		-Detnaviv=disabled -Dcairo-tests=disabled -Dman-pages=disabled -Dvalgrind=disabled \
		-Dtests=false -Dudev=false >libdrm-setup.log
	ninja -C libdrm-build install >libdrm-build.log
fi

# ---- Mesa (panfrost, with the G71 derivative fix) ----
if [ ! -d mesa-$MESA ]; then
	curl -fL https://archive.mesa3d.org/mesa-$MESA.tar.xz | tar -xJf -
	(cd mesa-$MESA && patch -p1 < "$TOP/tools/mesa-g71/0001-pan-bi-fix-derivatives-on-Mali-G71.patch")
fi
[ -x venv/bin/python ] || { python3 -m venv --system-site-packages venv && venv/bin/pip install -q mako pyyaml; }
export PATH=$W/native-install/bin:$W/venv/bin:$PATH
if [ ! -x native-install/bin/panfrost_compile ]; then
	# build-time tools for the host: Mesa's CL compiler and panfrost's kernel precompiler
	meson setup --wipe native mesa-$MESA --prefix="$W/native-install" --buildtype=release \
		-Dplatforms= -Dgallium-drivers=panfrost -Dvulkan-drivers= -Degl=disabled \
		-Dgbm=disabled -Dglx=disabled -Dgles1=disabled -Dgles2=disabled -Dopengl=false \
		-Dglvnd=disabled -Dllvm=enabled -Dmesa-clc=enabled -Dinstall-mesa-clc=true \
		-Dprecomp-compiler=enabled -Dinstall-precomp-compiler=true -Dvideo-codecs= \
		-Dvalgrind=disabled -Dlibunwind=disabled -Dlmsensors=disabled -Dbuild-tests=false \
		-Dgallium-va=disabled -Dgallium-rusticl=false -Dtools= >native-setup.log
	ninja -C native install >native-build.log
fi
[ -f mesa-build/build.ninja ] || meson setup mesa-build mesa-$MESA --cross-file android-aarch64.ini \
	--prefix=/vendor --libdir=lib64 --buildtype=release -Db_ndebug=true \
	-Dplatforms=android -Dplatform-sdk-version=$API -Dandroid-stub=true \
	-Dandroid-libbacktrace=disabled -Dgallium-drivers=panfrost -Dvulkan-drivers= \
	-Degl=enabled -Dgbm=disabled -Dglx=disabled -Dopengl=false -Dgles1=enabled \
	-Dgles2=enabled -Dllvm=disabled -Dmesa-clc=system -Dprecomp-compiler=system \
	-Dxmlconfig=disabled -Dzstd=disabled -Dvalgrind=disabled -Dlibunwind=disabled \
	-Dlmsensors=disabled -Dbuild-tests=false -Dvideo-codecs= -Dtools= \
	-Degl-lib-suffix=_mesa -Dgles-lib-suffix=_mesa -Dgallium-va=disabled \
	-Dgallium-rusticl=false -Dc_link_args=-static-libstdc++ \
	-Dcpp_link_args=-static-libstdc++ >mesa-setup.log
ninja -C mesa-build >mesa-build.log

rm -rf stage && mkdir -p $STAGE/egl $STAGE/hw
cp mesa-build/src/gallium/targets/dri/libgallium_dri.so $STAGE/
cp mesa-build/src/egl/libEGL_mesa.so mesa-build/src/mesa/glapi/es2api/libGLESv2_mesa.so \
	mesa-build/src/mesa/glapi/es1api/libGLESv1_CM_mesa.so $STAGE/egl/

I="-I$W/aosp-inc/liblog -I$W/aosp-inc/libcutils -I$W/aosp-inc/libsystem -I$W/aosp-inc/libsync"
I="$I -I$W/aosp-inc/libhardware -I$W/aosp-inc/nativewindow -I$W/aosp-inc/nativebase"
I="$I -I$W/prefix/include -I$W/prefix/include/libdrm"
LIBS="-static-libstdc++ $W/prefix/lib/libdrm.a -L$W/devlibs -llog -lcutils -lsync -ldl -lm"

# ---- minigbm gralloc0 ----
O=$W/minigbm-obj && rm -rf $O && mkdir -p $O
F="-fPIC -O2 -DHAS_NO_AIDL_METADATA -DDRV_EXYNOS_HEAP -D_GNU_SOURCE -DLOG_TAG=\"minigbm\" -Wno-unused-parameter"
(cd minigbm
for s in drv.c drv_helpers.c drv_array_helpers.c dumb_driver.c exynos_heap.c backend_mock.c \
	 virtgpu.c virtgpu_cross_domain.c virtgpu_virgl.c; do
	$CC $F $I -I. -Iexternal -std=gnu11 -c $s -o $O/${s%.c}.o
done
for s in cros_gralloc/cros_gralloc_buffer.cc cros_gralloc/cros_gralloc_driver.cc \
	 cros_gralloc/cros_gralloc_helpers.cc cros_gralloc/gralloc0/gralloc0.cc; do
	$CXX $F $I -I. -Iexternal -std=c++20 -Wno-invalid-offsetof -c $s -o $O/$(basename ${s%.cc}).o
done)
$CXX -shared -o $STAGE/hw/gralloc.minigbm.so $O/*.o -Wl,-soname,gralloc.minigbm.so -Wl,-z,defs $LIBS

# ---- drm_hwcomposer HWC2 module ----
# statsd reporters are no-ops and the few libui types are shimmed, so it only
# links against C-ABI libraries (the NDK's libc++ can't share C++ types with
# the platform's libbase/libui); libbase's string/property helpers are built in
O=$W/hwc-obj && rm -rf $O && mkdir -p $O
L=$W/aosp-inc/libbase
F="-fPIC -O2 -std=c++20 -DANDROID -DHWC2_INCLUDE_STRINGIFICATION -DHWC2_USE_CPP11 -DHAS_LIBSYNC"
F="$F -DLOG_TAG=\"drmhwc\" -Wno-unused-parameter -Wno-deprecated-declarations"
HI="-I. -I$A/shim $I -I$W/aosp-inc/libutils-src/include -I$L/include"
(cd drm-hwc2
for s in backend/BackendManager.cpp backend/ClientBackend.cpp backend/GenericBackend.cpp \
	 compositor/CompositionPlanner.cpp compositor/FlatteningController.cpp \
	 compositor/GenericCompositionPlanner.cpp compositor/LayerToPlaneJoiningPlan.cpp \
	 hwc/HwcDisplayConfigs.cpp hwc/HwcDisplay.cpp hwc/HwcLayer.cpp stats/Stats.cpp \
	 stats/StatsPoller.cpp utils/fd.cpp utils/properties.cpp drm/DrmAtomicStateManager.cpp \
	 drm/DrmConnector.cpp drm/DrmColorOp.cpp drm/DrmCrtc.cpp drm/DrmDevice.cpp \
	 drm/DrmDisplayPipeline.cpp drm/DrmEncoder.cpp drm/DrmFbImporter.cpp drm/DrmHwc.cpp \
	 drm/DrmMode.cpp drm/DrmPlane.cpp drm/DrmProperty.cpp drm/ResourceManager.cpp \
	 drm/UEventListener.cpp drm/VSyncWorker.cpp bufferinfo/BufferInfoGetter.cpp \
	 bufferinfo/legacy/BufferInfoMinigbm.cpp hwc2_device/hwc2_device.cpp \
	 hwc2_device/DrmHwcTwo.cpp "$A/shim/stats_stubs.cpp" $L/strings.cpp $L/properties.cpp \
	 $L/stringprintf.cpp $L/parsebool.cpp $L/posix_strerror_r.cpp; do
	$CXX $F $HI -c $s -o $O/$(echo $s | tr '/' '_').o
done)
$CXX -shared -o $STAGE/hw/hwcomposer.drm.so $O/*.o -Wl,-soname,hwcomposer.drm.so -Wl,-z,defs \
	$LIBS -lhardware

$STRIP --strip-unneeded $STAGE/*.so $STAGE/egl/*.so $STAGE/hw/*.so
du -ah stage
