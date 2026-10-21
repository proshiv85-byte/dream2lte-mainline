/* gpioget CHIP LINE - read one GPIO line through the v2 chardev ABI */
#include <fcntl.h>
#include <linux/gpio.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>

int main(int argc, char **argv)
{
	struct gpio_v2_line_request req;
	struct gpio_v2_line_values vals = { .mask = 1 };
	int fd;

	if (argc < 3)
		return 2;
	fd = open(argv[1], O_RDONLY);
	if (fd < 0) {
		perror(argv[1]);
		return 1;
	}
	memset(&req, 0, sizeof(req));
	req.offsets[0] = atoi(argv[2]);
	req.num_lines = 1;
	req.config.flags = GPIO_V2_LINE_FLAG_INPUT;
	strcpy(req.consumer, "gpioget");
	if (ioctl(fd, GPIO_V2_GET_LINE_IOCTL, &req) < 0) {
		perror("request");
		return 1;
	}
	if (ioctl(req.fd, GPIO_V2_LINE_GET_VALUES_IOCTL, &vals) < 0) {
		perror("get");
		return 1;
	}
	printf("%d\n", (int)(vals.bits & 1));
	return 0;
}
