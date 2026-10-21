/* devmem ADDR [VALUE] - 32-bit physical memory read/write */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <unistd.h>

int main(int argc, char **argv)
{
	unsigned long addr, page;
	volatile uint32_t *p;
	void *map;
	int fd;

	if (argc < 2)
		return 2;
	addr = strtoul(argv[1], NULL, 0);
	page = addr & ~0xfffUL;
	fd = open("/dev/mem", O_RDWR | O_SYNC);
	if (fd < 0) {
		perror("/dev/mem");
		return 1;
	}
	map = mmap(NULL, 0x1000, PROT_READ | PROT_WRITE, MAP_SHARED, fd, page);
	if (map == MAP_FAILED) {
		perror("mmap");
		return 1;
	}
	p = (volatile uint32_t *)((char *)map + (addr - page));
	if (argc > 2)
		*p = strtoul(argv[2], NULL, 0);
	printf("0x%08x\n", *p);
	return 0;
}
