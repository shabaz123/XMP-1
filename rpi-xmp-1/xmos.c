/******************************************************
 * xmos.c
 * SPI interface to XMOS startKIT
 * 
 * rev. 1 - Initial version - shabaz
 *
 * Based on spidev.c, this code implements
 * a TLV (tag,length, value) protocol
 * to control data flow between the 
 * Linux platform (e.g. Raspberry Pi) and
 * the XMOS startKIT board in both directions.
 * The example code here is used to control up to
 * 8 servos
 ******************************************************/

#include <stdio.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>
#include <sys/ioctl.h>
#include <stdint.h>
#include <linux/spi/spidev.h>
#include <unistd.h> // sleep

typedef struct spi_ioc_transfer spi_t;
extern int errno;
static const char *device = "/dev/spidev0.1";

int
main(int argc, char* argv[])
{
	int fd;
	int ret;
	int i;
	uint8_t spi_config=0;
	uint8_t spi_bits=8;
	uint32_t spi_speed; //=32768;
	spi_speed=32768000; // this can take a few specific values
	spi_t spi;
	unsigned char txbuf[20];
	unsigned char rxbuf[20];
	int j;
	unsigned int servo[8];
	
	fprintf(stderr, "Hello stderr from app\n");
	fprintf(stdout, "Hello stdout from app\n");
	printf("Hello printf from app\n");
	
	fd=open(device, O_RDWR);
	if (fd<0)
	{
		fprintf(stderr, "Error opening device: %s\n", strerror(errno));
		exit(1);
  }
  
  //spi_config |= SPI_CS_HIGH;
  ret=ioctl(fd, SPI_IOC_WR_MODE, &spi_config);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI write mode: %s\n", strerror(errno));
		exit(1);
  }
  ret=ioctl(fd, SPI_IOC_RD_MODE, &spi_config);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI read mode: %s\n", strerror(errno));
		exit(1);
  }
  ret=ioctl(fd, SPI_IOC_WR_BITS_PER_WORD, &spi_bits);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI write bits: %s\n", strerror(errno));
		exit(1);
  }
  ret=ioctl(fd, SPI_IOC_RD_BITS_PER_WORD, &spi_bits);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI read bits: %s\n", strerror(errno));
		exit(1);
  }
  ret=ioctl(fd, SPI_IOC_WR_MAX_SPEED_HZ, &spi_speed);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI write speed: %s\n", strerror(errno));
		exit(1);
  }
  ret=ioctl(fd, SPI_IOC_RD_MAX_SPEED_HZ, &spi_speed);
  if (ret<0)
  {
  	fprintf(stderr, "Error setting SPI read speed: %s\n", strerror(errno));
		exit(1);
  }
  
  servo[0]=2000;
  servo[1]=1700;
  servo[2]=1300;
  servo[3]=1000;
  servo[4]=1500;
  servo[5]=1500;
  servo[6]=1500;
  servo[7]=1500;
  
  	if (argc>=3)
	{
		sscanf(argv[1], "%d", &servo[0]);
		sscanf(argv[2], "%d", &servo[1]);
		printf ("servo 0,1 are %d, %d\n", servo[0], servo[1]);
	}
  
  // send to tag 0x02
  for (i=0; i<20; i++)
  {
  	rxbuf[i]=0;
  }
  txbuf[0]=0x02;
  txbuf[1]=0x00;
  txbuf[2]=0x10;
  j=3;
  for (i=0; i<8; i++)
  {
  	txbuf[j++]=(servo[i] & 0xff00)>>8;
  	txbuf[j++]=(servo[i] & 0x00ff);
 	}
  
  spi.delay_usecs=0;
  spi.speed_hz=spi_speed;
  spi.bits_per_word=spi_bits;
  spi.cs_change=0;
  spi.tx_buf=(unsigned long)txbuf;
  spi.rx_buf=(unsigned long)rxbuf;
  spi.len=19;

  ret=ioctl(fd, SPI_IOC_MESSAGE(1), &spi);
  if (ret<0)
  {
  	fprintf(stderr, "Error performing SPI exchange: %s\n", strerror(errno));
		exit(1);
  }
  
  // just some debug stuff, unnecessary:
  for (i=0; i<4; i++)
  {
		printf("0x%0x,", rxbuf[i]);
	}
	printf("\n");
	
  close(fd);
  
  return(0);
}
