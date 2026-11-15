#pragma once
// standalone-build shim: BT.2020 primaries / D65 white point only
#include <array>
namespace android {
struct ColorSpaceXY { float x, y; };
class ColorSpace {
 public:
  static ColorSpace BT2020() { return ColorSpace(); }
  std::array<ColorSpaceXY, 3> getPrimaries() const {
    return {{{0.708f, 0.292f}, {0.170f, 0.797f}, {0.131f, 0.046f}}};
  }
  ColorSpaceXY getWhitePoint() const { return {0.3127f, 0.3290f}; }
};
}  // namespace android
