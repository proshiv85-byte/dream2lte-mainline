/* reboot(2) with a command string: "rbt recovery" -> TWRP, "rbt" -> normal */
#include <linux/reboot.h>
#include <asm/unistd.h>

static long sys(long n, long a, long b, long c, long d)
{
	register long x8 asm("x8") = n;
	register long x0 asm("x0") = a;
	register long x1 asm("x1") = b;
	register long x2 asm("x2") = c;
	register long x3 asm("x3") = d;

	asm volatile("svc #0" : "+r"(x0) : "r"(x8), "r"(x1), "r"(x2), "r"(x3) : "memory");
	return x0;
}

void __attribute__((noreturn)) _start_c(long *sp)
{
	long argc = sp[0];
	char **argv = (char **)(sp + 1);

	sys(__NR_sync, 0, 0, 0, 0);
	if (argc > 1)
		sys(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		    LINUX_REBOOT_CMD_RESTART2, (long)argv[1]);
	else
		sys(__NR_reboot, LINUX_REBOOT_MAGIC1, LINUX_REBOOT_MAGIC2,
		    LINUX_REBOOT_CMD_RESTART, 0);
	sys(__NR_exit, 1, 0, 0, 0);
	for (;;)
		;
}

asm(".globl _start\n_start:\n\tmov x0, sp\n\tb _start_c\n");
