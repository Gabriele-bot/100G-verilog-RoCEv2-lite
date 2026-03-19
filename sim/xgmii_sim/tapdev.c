#include <stdio.h>
#include <stdlib.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <signal.h>
#include <time.h>
#include <netinet/in.h>
#include <netinet/ip6.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <net/route.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <linux/if.h>
#include <linux/if_tun.h>
#include <linux/if_ether.h>
#include <time.h>
#include <errno.h>
#include "buffer.h"

static volatile int keepRunning = 1;

void intHandler(int dummy) { keepRunning = 0; printf("\nExiting...\n"); }


RingBuffer_t * tap2mac;
RingBuffer_t * mac2tap;
struct timespec tss;

/*
* create shared ring buffers
*/
void shared_mem_init()
{
    int size = sizeof( RingBuffer_t );
    int fd = shm_open( SHM_ID_TAP2MAC, O_RDWR | O_CREAT, 0666);
    if ( fd < 0) {perror("Shared memory error:"); exit(-1);}
    if(ftruncate( fd, size+1 ) < 0) {perror("ftruncate"); exit(-1);}

    // create shared memory area
    tap2mac = (RingBuffer_t*)mmap( 0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0 );
    if (tap2mac == MAP_FAILED) {perror("tap2mac mmap"); exit(-1);}
    close( fd );

    fd = shm_open( SHM_ID_MAC2TAP, O_RDWR | O_CREAT, 0666 );
    if ( fd < 0) {perror("Shared memory error:"); exit(-1);}
    if(ftruncate( fd, size+1 ) < 0) {perror("ftruncate"); exit(-1);}

    // create shared memory area
    mac2tap = (RingBuffer_t*)mmap( 0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0 );
    if (mac2tap == MAP_FAILED) {perror("mac2tap mmap"); exit(-1);}
    close( fd );

    // initialize our sequence numbers in the ring buffer
    tap2mac->_wseq = tap2mac->_rseq = 0;
    mac2tap->_wseq = mac2tap->_rseq = 0;

    tss.tv_sec = 0;
    tss.tv_nsec = SLEEP_NANOS;

    //printf("tap2mac 0x%x\n",(unsigned int) tap2mac->_wseq);
    //printf("mac2tap 0x%x\n",(unsigned int) mac2tap->_wseq);
}



/*
* checksum calculation
*/

static unsigned short ip_checksum(char * data,int length) {

    // Initialise the accumulator.
    unsigned int  acc=0xffff;

    // Handle complete 16-bit blocks.
    for (int i=0;i+1<length;i+=2) {
        unsigned short word;
        memcpy(&word,data+i,2);
        acc+=ntohs(word);
        if (acc>0xffff) {
            acc-=0xffff;
        }
    }

    // Handle any partial block at the end of the data.
    if (length&1) {
        unsigned short word=0;
        memcpy(&word,data+length-1,1);
        acc+=ntohs(word);
        if (acc>0xffff) {
            acc-=0xffff;
        }
    }

    // Return the checksum in network byte order.
    return htons(~acc);
}

/*
*  tap create
*/
int tap_init(char *dev)
{
	struct ifreq ifr;
	int fd, err;
        uid_t owner = -1;

	fd = open("/dev/net/tun", O_RDWR | O_NONBLOCK);
	if (fd < 0) {
		perror("open");
		exit(1);
	}

	memset(&ifr, 0, sizeof(ifr));
	ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
	if (*dev) {
		strncpy(ifr.ifr_name, dev, IFNAMSIZ);
	}

	err = ioctl(fd, TUNSETIFF, (void *)&ifr);
	if (err < 0) {
		perror("TUNSETIFF");
		close(fd);
		exit(1);
	}
	strcpy(dev, ifr.ifr_name);

        if(ioctl(fd, TUNSETPERSIST, 0) < 0){
                perror("disabling TUNSETPERSIST");
                exit(1);
        }
        printf("Set '%s' nonpersistent\n", ifr.ifr_name);

        owner = geteuid();
        if(ioctl(fd, TUNSETOWNER, owner) < 0){
      	        perror("TUNSETOWNER");
      	        exit(1);
        }

	return fd;
}

/*
* cwrite: write routine that checks for errors
*/
int cwrite(int fd, unsigned char *buf, int n){

  int nwrite;

  if((nwrite=write(fd, buf, n)) < 0){ perror("cwrite"); return(0); }
  return nwrite;
}

/*
* mac_emulator
* emulates media access controller functions
* e.g : computes IP layer total length and IP header checksum
* and writes them in appropriate fields of the packet
*/
void mac_emulate(unsigned char *buf, int cnt)
{
        const int START_OF_IP_HEADER = 0xe;
        const int IP_HEADER_CKS_OFS = 0x18;
        const int ETH_FIELD_OFS = 0xc;
        const int IP_PROTO_FIELD_OFS = 0x17;
        const int IP_TOT_LENGHT_FIELD_OFS = 0x10;
        const int ETH_HEADER_SIZE = 14;

        unsigned short * sptr;
        unsigned char * ptr;
        unsigned short cks;
        unsigned int tot_len = 0;

        // checks if it is a IP packet
        sptr = (unsigned short *) (buf+ETH_FIELD_OFS);
        if(*sptr == 0x0008) {  // 0x0800 = ETH ; big endian
           ptr = buf + IP_PROTO_FIELD_OFS;
           if(*ptr == 0x1) {   // 1 == IP 

                // compute tot length 
                sptr = (unsigned short *) (buf + IP_TOT_LENGHT_FIELD_OFS);
                tot_len = cnt - ETH_HEADER_SIZE;
                // write it big endian
                *sptr = (tot_len >> 8) | (tot_len << 8);

                // compute IP HEADER checksum and write it
                sptr= (unsigned short *) (buf + IP_HEADER_CKS_OFS);
                *sptr = 0x0;
                ptr = (buf + START_OF_IP_HEADER);
                cks = ip_checksum((char *)ptr,20); 
                sptr= (unsigned short *) (buf + IP_HEADER_CKS_OFS);
                // write big endian
                *sptr = cks;

                }
           }
}

/*
* tap2mac ring buffer empty
*/
inline int tap2mac_full()
{
        if( (tap2mac->_wseq+1)%NUM_PACKETS == tap2mac->_rseq%NUM_PACKETS ) {
             return 1;
        } else{ return 0; }
}

/*
* mac2tap ring buffer full
*/
int mac2tap_empty()
{
        if( mac2tap->_wseq%NUM_PACKETS == mac2tap->_rseq%NUM_PACKETS ) 
             return 1;
        else
             return 0;
}

/*
* tap_empty
*/
unsigned short tap_empty(int tap_fd)
{
        unsigned char * buf;
        short frame_len;

        buf = (unsigned char *) tap2mac->_buffer[tap2mac->_wseq].data;
        frame_len = read(tap_fd, buf, MAX_PACKET_SIZE);
        if (frame_len < 0) { 
            if (errno = EAGAIN) return 0;
            else {perror("Tap read"); exit (0);}
        }
        return frame_len;
}


static long id=0;
/*
* pktout
*/
void pktout(unsigned short frame_len)
{
        tap2mac->_buffer[tap2mac->_wseq].len = frame_len;
        tap2mac->_buffer[tap2mac->_wseq].id = id++;
        tap2mac->_wseq = (tap2mac->_wseq +1) % NUM_PACKETS;
}

/*
* pktin
*/
int pktin(int tap_fd)
{
        unsigned short cnt;
        unsigned char * buf;

        buf = (unsigned char *)mac2tap->_buffer[mac2tap->_rseq].data;
        cnt = mac2tap->_buffer[mac2tap->_rseq].len;
        mac2tap->_rseq = (mac2tap->_rseq +1) % NUM_PACKETS;

	//fprintf(stderr, "gmii -> tap :: cnt=%d\n", cnt);
        mac_emulate(buf, cnt);
	return cwrite(tap_fd, buf, cnt);
}

/*
* main
*/
int main(int argc, char **argv)
{
	char dev[IFNAMSIZ];
	int tap_fd;
        unsigned short frame_len;

	if (argc < 2) {
		fprintf(stderr, "Usage:%s {devicename}\n", argv[0]);
		return 1;
	}
	strcpy(dev, argv[1]);

        shared_mem_init();

	tap_fd = tap_init(dev);


        signal(SIGINT, intHandler);

	while(keepRunning) {

		// pktout
                if( !tap2mac_full() ) {
                        // check if packet exists in the tap i/f
                        frame_len = tap_empty(tap_fd);
                        if(frame_len) {
                              //printf("frame len %d id %d\n",frame_len,tap2mac->_wseq);
			      pktout(frame_len);
                        }
                } else printf("tap2mac ring buffer full : dropping packet\n");

		// pktin
		if (!mac2tap_empty()) {
			pktin(tap_fd);
		}
                usleep(10);
	}
	close(tap_fd);

	exit(0);
}

