#pragma once
// standalone-build shim: only what drm_hwcomposer's HWC2 path uses
#include <cstdint>
namespace aidl::android::hardware::graphics::common {
enum class Hdr : int32_t { INVALID = 0, DOLBY_VISION = 1, HDR10 = 2, HLG = 3, HDR10_PLUS = 4 };
}
namespace android::ui {
using aidl::android::hardware::graphics::common::Hdr;
}
