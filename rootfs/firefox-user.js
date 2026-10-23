// touchscreen: pinch to zoom pages (armtix)
user_pref("dom.w3c_touch_events.enabled", 1);
user_pref("apz.allow_zooming", true);
user_pref("apz.allow_double_tap_zooming", true);
// phone-style zoom: pages are laid out like on a phone browser (desktop
// sites zoomed out to fit), so a pinch can zoom both in and out
user_pref("dom.meta-viewport.enabled", true);
// the optimized WebRender shaders draw rounded clips as blocks on Mali
// (panfrost and the Android driver alike); the plain ones are fine
user_pref("gfx.webrender.use-optimized-shaders", false);
