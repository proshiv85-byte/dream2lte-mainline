// touchscreen: pinch to zoom pages (armtix)
user_pref("dom.w3c_touch_events.enabled", 1);
user_pref("apz.allow_zooming", true);
user_pref("apz.allow_double_tap_zooming", true);
// phone-style zoom: pages are laid out like on a phone browser (desktop
// sites zoomed out to fit), so a pinch can zoom both in and out
user_pref("dom.meta-viewport.enabled", true);
