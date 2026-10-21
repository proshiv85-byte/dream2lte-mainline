/* i2c BUS ADDR REG [VAL] - SMBus byte read/write through /dev/i2c-BUS */
#include <fcntl.h>
#include <linux/i2c.h>
#include <linux/i2c-dev.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <unistd.h>

static int smbus(int fd, char rw, int reg, int size, union i2c_smbus_data *d)
{
	struct i2c_smbus_ioctl_data args = { rw, reg, size, d };

	return ioctl(fd, I2C_SMBUS, &args);
}

int main(int argc, char **argv)
{
	union i2c_smbus_data d;
	char dev[32];
	int fd, reg;

	if (argc < 4) {
		fprintf(stderr, "usage: %s BUS ADDR REG [VAL]\n", argv[0]);
		return 2;
	}
	snprintf(dev, sizeof(dev), "/dev/i2c-%s", argv[1]);
	fd = open(dev, O_RDWR);
	if (fd < 0 || ioctl(fd, I2C_SLAVE_FORCE, strtol(argv[2], NULL, 0)) < 0) {
		perror(dev);
		return 1;
	}
	reg = strtol(argv[3], NULL, 0);
	if (argc > 4 && argv[4][0] == 'r') {
		/* I2C block read of N bytes: i2c BUS ADDR REG rN */
		int i, n = atoi(argv[4] + 1);

		d.block[0] = n;
		if (smbus(fd, I2C_SMBUS_READ, reg, I2C_SMBUS_I2C_BLOCK_DATA, &d) < 0) {
			perror("block read");
			return 1;
		}
		for (i = 1; i <= n; i++)
			printf("%02x ", d.block[i]);
		printf("\n");
		return 0;
	}
	if (argc > 4 && argv[4][0] == 'b') {
		/* I2C block write: i2c BUS ADDR REG b BYTE... */
		int i;

		d.block[0] = argc - 5;
		for (i = 5; i < argc; i++)
			d.block[i - 4] = strtol(argv[i], NULL, 0);
		if (smbus(fd, I2C_SMBUS_WRITE, reg, I2C_SMBUS_I2C_BLOCK_DATA, &d) < 0) {
			perror("block write");
			return 1;
		}
		printf("ok\n");
		return 0;
	}
	if (argc > 4 && argv[4][0] == 'c') {
		/* single command byte: i2c BUS ADDR CMD c */
		if (smbus(fd, I2C_SMBUS_WRITE, reg, I2C_SMBUS_BYTE, NULL) < 0) {
			perror("command");
			return 1;
		}
		printf("ok\n");
		return 0;
	}
	if (argc > 4) {
		d.byte = strtol(argv[4], NULL, 0);
		if (smbus(fd, I2C_SMBUS_WRITE, reg, I2C_SMBUS_BYTE_DATA, &d) < 0) {
			perror("write");
			return 1;
		}
	}
	if (smbus(fd, I2C_SMBUS_READ, reg, I2C_SMBUS_BYTE_DATA, &d) < 0) {
		perror("read");
		return 1;
	}
	printf("0x%02x\n", d.byte);
	return 0;
}
