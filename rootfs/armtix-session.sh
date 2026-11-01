# /etc/profile.d/armtix-session.sh: logins outside the sway session (SSH,
# text consoles) get its display, so graphical programs open on the phone
# screen out of the box, with the same GPU environment as in sway.
# Nothing happens inside sway (WAYLAND_DISPLAY is set there already) or
# while sway isn't running.
if [ -z "$WAYLAND_DISPLAY" ]; then
	# our own session first; root takes the first one it finds
	for _w in /run/user/$(id -u)/wayland-[0-9] /run/user/*/wayland-[0-9]; do
		[ -S "$_w" ] || continue
		[ -O "$_w" ] || [ "$(id -u)" = 0 ] || continue
		_d=${_w%/*}
		if [ -O "$_w" ]; then
			export XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR:-$_d}
			export WAYLAND_DISPLAY=${_w##*/}
		else
			# someone else's session: the socket by its full path
			export WAYLAND_DISPLAY=$_w
		fi
		for _s in "$_d"/sway-ipc.*.sock; do
			[ -S "$_s" ] && export SWAYSOCK=$_s
		done
		# Xwayland (sway starts it on the first X client)
		[ -z "$DISPLAY" ] && [ -S /tmp/.X11-unix/X0 ] && export DISPLAY=:0
		export XDG_SESSION_TYPE=wayland
		[ -f /usr/local/lib/armtix/gpu-env ] && . /usr/local/lib/armtix/gpu-env
		break
	done
	unset _w _d _s
fi
