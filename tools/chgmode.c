// SPDX-License-Identifier: GPL-2.0
/*
 * Off-mode charging for the initramfs: run when S-Boot powered the phone on
 * because a charger was plugged in (androidboot.mode=charger), instead of
 * booting the system.
 *
 * Shows the battery level on the framebuffer for a few seconds, then turns
 * the screen off (black, see screen()); a short press of the power key shows it again. Holding
 * the power key for HOLD_MS exits with 0, so the initramfs boots normally.
 * Unplugging the charger powers the phone off. The kernel's charger driver
 * does the charging itself.
 *
 *   chgmode          the loop above
 *   chgmode -s N     draw the screen once, keep it N seconds, exit (testing)
 */

#include <fcntl.h>
#include <linux/fb.h>
#include <linux/input.h>
#include <linux/reboot.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/mman.h>
#include <sys/reboot.h>
#include <time.h>
#include <unistd.h>

#define CHARGER		"/sys/class/power_supply/max77865-charger/online"
#define CAPACITY	"/sys/class/power_supply/max170xx_battery/capacity"
#define STATUS		"/sys/class/power_supply/max170xx_battery/status"

#define SHOW_MS		5000	/* screen on after start or a key press */
#define HOLD_MS		1500	/* power key held this long: boot */
#define UNPLUG_MS	3000	/* charger gone this long: power off */
#define TICK_MS		1000

static struct fb_var_screeninfo var;
static struct fb_fix_screeninfo fix;
static unsigned char *fbmem;
static int fbfd = -1;

static long long now_ms(void)
{
	struct timespec ts;

	clock_gettime(CLOCK_MONOTONIC, &ts);
	return ts.tv_sec * 1000LL + ts.tv_nsec / 1000000;
}

static void klog(const char *msg)
{
	int fd = open("/dev/kmsg", O_WRONLY);

	if (fd >= 0) {
		dprintf(fd, "chgmode: %s\n", msg);
		close(fd);
	}
}

static int read_int(const char *path, int def)
{
	char buf[32];
	int fd = open(path, O_RDONLY), n;

	if (fd < 0)
		return def;
	n = read(fd, buf, sizeof(buf) - 1);
	close(fd);
	if (n <= 0)
		return def;
	buf[n] = 0;
	return atoi(buf);
}

static int is_full(void)
{
	char buf[32] = "";
	int fd = open(STATUS, O_RDONLY);

	if (fd >= 0) {
		if (read(fd, buf, sizeof(buf) - 1) < 0)
			buf[0] = 0;
		close(fd);
	}
	return !strncmp(buf, "Full", 4);
}

/* the input device with KEY_POWER */
static int open_power_key(void)
{
	unsigned long bits[KEY_MAX / (8 * sizeof(long)) + 1];
	char path[64];
	int i, fd;

	for (i = 0; i < 16; i++) {
		snprintf(path, sizeof(path), "/dev/input/event%d", i);
		fd = open(path, O_RDONLY | O_NONBLOCK);
		if (fd < 0)
			continue;
		memset(bits, 0, sizeof(bits));
		if (ioctl(fd, EVIOCGBIT(EV_KEY, sizeof(bits)), bits) >= 0 &&
		    (bits[KEY_POWER / (8 * sizeof(long))] >>
		     (KEY_POWER % (8 * sizeof(long)))) & 1)
			return fd;
		close(fd);
	}
	return -1;
}

/* ---- drawing ---- */

static unsigned int rgb(unsigned int r, unsigned int g, unsigned int b)
{
	return (r >> (8 - var.red.length)) << var.red.offset |
	       (g >> (8 - var.green.length)) << var.green.offset |
	       (b >> (8 - var.blue.length)) << var.blue.offset;
}

static void rect(int x, int y, int w, int h, unsigned int c)
{
	int i, j;

	for (j = y; j < y + h; j++) {
		unsigned int *row;

		if (j < 0 || j >= (int)var.yres)
			continue;
		row = (unsigned int *)(fbmem + (size_t)(j + var.yoffset) *
				       fix.line_length);
		for (i = x; i < x + w; i++)
			if (i >= 0 && i < (int)var.xres)
				row[i] = c;
	}
}

/* 5x7 digits and '%', one row per byte, bit 4 is the leftmost column */
static const unsigned char glyphs[11][7] = {
	{ 0x0e, 0x11, 0x13, 0x15, 0x19, 0x11, 0x0e },	/* 0 */
	{ 0x04, 0x0c, 0x04, 0x04, 0x04, 0x04, 0x0e },	/* 1 */
	{ 0x0e, 0x11, 0x01, 0x02, 0x04, 0x08, 0x1f },	/* 2 */
	{ 0x1f, 0x02, 0x04, 0x02, 0x01, 0x11, 0x0e },	/* 3 */
	{ 0x02, 0x06, 0x0a, 0x12, 0x1f, 0x02, 0x02 },	/* 4 */
	{ 0x1f, 0x10, 0x1e, 0x01, 0x01, 0x11, 0x0e },	/* 5 */
	{ 0x06, 0x08, 0x10, 0x1e, 0x11, 0x11, 0x0e },	/* 6 */
	{ 0x1f, 0x01, 0x02, 0x04, 0x08, 0x08, 0x08 },	/* 7 */
	{ 0x0e, 0x11, 0x11, 0x0e, 0x11, 0x11, 0x0e },	/* 8 */
	{ 0x0e, 0x11, 0x11, 0x0f, 0x01, 0x02, 0x0c },	/* 9 */
	{ 0x18, 0x19, 0x02, 0x04, 0x08, 0x13, 0x03 },	/* % */
};

static void glyph(int g, int x, int y, int px, unsigned int c)
{
	int r, col;

	for (r = 0; r < 7; r++)
		for (col = 0; col < 5; col++)
			if (glyphs[g][r] & (0x10 >> col))
				rect(x + col * px, y + r * px, px, px, c);
}

/* push it out: drm's fbdev emulation flushes on a pan */
static void flush(void)
{
	ioctl(fbfd, FBIOPAN_DISPLAY, &var);
}

static void draw(int cap)
{
	/* a battery a fifth of the width, the percentage below, centred */
	int w = var.xres, h = var.yres;
	int bw = w / 5, bh = bw * 2, t = bw / 12, px = w / 90;
	int gap = bh / 6, by = (h - (bh + gap + 7 * px)) / 2, bx = (w - bw) / 2;
	int fill, n = 0, g[4], i, x;
	unsigned int white = rgb(0xe0, 0xe0, 0xe0), black = rgb(0, 0, 0);
	unsigned int level = cap < 15 ? rgb(0xe0, 0x30, 0x30) :
			     rgb(0x30, 0xc0, 0x50);

	if (cap < 0)
		cap = 0;
	if (cap > 100)
		cap = 100;

	rect(0, 0, w, h, black);

	/* battery: cap, outline, level from the bottom */
	rect(bx + bw / 3, by - t * 3, bw / 3, t * 3, white);
	rect(bx, by, bw, t, white);
	rect(bx, by + bh - t, bw, t, white);
	rect(bx, by, t, bh, white);
	rect(bx + bw - t, by, t, bh, white);
	fill = (bh - 4 * t) * cap / 100;
	rect(bx + 2 * t, by + bh - 2 * t - fill, bw - 4 * t, fill,
	     is_full() ? white : level);

	/* the percentage below it */
	if (cap == 100)
		g[n++] = 1, g[n++] = 0, g[n++] = 0;
	else if (cap >= 10)
		g[n++] = cap / 10, g[n++] = cap % 10;
	else
		g[n++] = cap;
	g[n++] = 10;
	x = (w - (n * 6 - 1) * px) / 2;
	for (i = 0; i < n; i++)
		glyph(g[i], x + i * 6 * px, by + bh + gap, px, white);

	flush();
}

static int fb_open(void)
{
	fbfd = open("/dev/fb0", O_RDWR);
	if (fbfd < 0)
		return -1;
	if (ioctl(fbfd, FBIOGET_VSCREENINFO, &var) < 0 ||
	    ioctl(fbfd, FBIOGET_FSCREENINFO, &fix) < 0 ||
	    var.bits_per_pixel != 32)
		goto fail;
	fbmem = mmap(NULL, fix.smem_len, PROT_READ | PROT_WRITE, MAP_SHARED,
		     fbfd, 0);
	if (fbmem == MAP_FAILED)
		goto fail;
	return 0;
fail:
	close(fbfd);
	fbfd = -1;
	return -1;
}

/*
 * In the initramfs the framebuffer is simpledrm on the bootloader's buffer,
 * which can't turn the panel off; the panel is AMOLED, so black is off as
 * far as anyone can see. The blank is for a display driver that can.
 */
static void screen(int on)
{
	if (fbfd < 0)
		return;
	if (!on) {
		rect(0, 0, var.xres, var.yres, rgb(0, 0, 0));
		flush();
	}
	ioctl(fbfd, FBIOBLANK, on ? FB_BLANK_UNBLANK : FB_BLANK_POWERDOWN);
}

int main(int argc, char **argv)
{
	long long t, shown = 0, pressed = 0, unplugged = 0;
	int key, on = 0;

	/* the console cursor would blink over the picture */
	int tty = open("/dev/tty0", O_WRONLY);

	if (tty >= 0) {
		if (write(tty, "\033[?25l\033[2J", 10) < 0)
			;
		close(tty);
	}

	if (fb_open() < 0)
		klog("no framebuffer, charging with the screen off");

	if (argc == 3 && !strcmp(argv[1], "-s")) {
		if (fbfd < 0)
			return 1;
		screen(1);
		draw(read_int(CAPACITY, 0));
		sleep(atoi(argv[2]));
		return 0;
	}

	key = open_power_key();
	if (key < 0)
		klog("no power key found");
	klog("off-mode charging: hold power to boot, unplug to power off");

	for (;;) {
		struct pollfd pfd = { .fd = key, .events = POLLIN };
		struct input_event ev;
		int timeout = TICK_MS;

		t = now_ms();

		/* screen: on for SHOW_MS after start or a short press */
		if (!shown || (pressed == 0 && shown < 0)) {
			shown = t;
			if (!on)
				screen(1);
			on = 1;
		}
		if (on && fbfd >= 0)
			draw(read_int(CAPACITY, 0));
		if (on && t - shown >= SHOW_MS) {
			screen(0);
			on = 0;
		}

		/* charger gone: power off */
		if (read_int(CHARGER, 1) == 0) {
			if (!unplugged)
				unplugged = t;
			else if (t - unplugged >= UNPLUG_MS) {
				klog("charger unplugged, powering off");
				sync();
				reboot(LINUX_REBOOT_CMD_POWER_OFF);
			}
		} else {
			unplugged = 0;
		}

		/* power key held long enough: boot */
		if (pressed) {
			if (t - pressed >= HOLD_MS) {
				klog("power key held, booting");
				screen(1);
				return 0;
			}
			timeout = HOLD_MS - (t - pressed);
		}

		if (key < 0) {
			poll(NULL, 0, timeout);
			continue;
		}
		if (poll(&pfd, 1, timeout) <= 0)
			continue;
		while (read(key, &ev, sizeof(ev)) == sizeof(ev)) {
			if (ev.type != EV_KEY || ev.code != KEY_POWER)
				continue;
			if (ev.value == 1) {
				pressed = now_ms();
			} else if (ev.value == 0) {
				/* a short press: show the screen again */
				pressed = 0;
				shown = -1;
			}
		}
	}
}
