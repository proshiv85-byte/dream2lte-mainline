// no-op statsd atom reporters for the standalone (non-AOSP) build
#include "compositor/FlatteningEventAtomReporter.h"
#include "stats/CompositionStatsAtomReporter.h"
#include "stats/CountActiveDisplaysReporter.h"
#include "stats/DisplayHotplugConnectModeDetectedAtomReporter.h"
#include "stats/DisplayRefreshRatesChangedAtomReporter.h"
namespace android::drm_hwcomposer {
namespace {
struct NoComp : CompositionStatsAtomReporter {
  void PushAtom(int64_t, bool, ValidationResult, CompositionPlanner::FlattenReason, int64_t, int64_t,
                int64_t, uint64_t, uint64_t) override {}
};
struct NoCount : CountActiveDisplaysReporter { void PushAtom(int32_t, int32_t, int32_t) override {} };
struct NoHotplug : DisplayHotplugConnectModeDetectedAtomReporter { void PushAtom(Atom) override {} };
struct NoRates : DisplayRefreshRatesChangedAtomReporter { void UpdateRefreshRates(std::vector<int32_t>) override {} };
struct NoFlat : FlatteningEventAtomReporter { void PushAtom(int64_t, FlatteningController::State) override {} };
}  // namespace
std::unique_ptr<CompositionStatsAtomReporter> CompositionStatsAtomReporter::Create() { return std::make_unique<NoComp>(); }
std::unique_ptr<CountActiveDisplaysReporter> CountActiveDisplaysReporter::Create() { return std::make_unique<NoCount>(); }
std::unique_ptr<DisplayHotplugConnectModeDetectedAtomReporter> DisplayHotplugConnectModeDetectedAtomReporter::Create() { return std::make_unique<NoHotplug>(); }
std::unique_ptr<DisplayRefreshRatesChangedAtomReporter> DisplayRefreshRatesChangedAtomReporter::Create() { return std::make_unique<NoRates>(); }
std::unique_ptr<FlatteningEventAtomReporter> FlatteningEventAtomReporter::Create() { return std::make_unique<NoFlat>(); }
}  // namespace android::drm_hwcomposer
