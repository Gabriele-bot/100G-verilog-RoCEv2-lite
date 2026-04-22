#include <stdio.h>
#include <stdbool.h>
#include <string.h>
#include <errno.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/select.h>
#include <svdpi.h>
#include "vc_hdrs.h"
#include "buffer.h"

#define XGMII_PREAMBLE  0xD5555555555555FB

extern void xgmii_write(long long, char);
extern void xgmii_idle(void);


RingBuffer_t * tap2mac;
RingBuffer_t * mac2tap;
struct timespec tss;

/*
* opens shared ring buffers
* they must first be created by tapdev
*/
 int shared_mem_init()
{
    int size = sizeof( RingBuffer_t );
    int fd = shm_open( SHM_ID_TAP2MAC, O_RDWR , 0600 );
    if ( fd < 0) {perror("Shared memory error:"); exit(-1);}
    
    

    // create shared memory area
    tap2mac = (RingBuffer_t*)mmap( 0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0 );
    close( fd );

    fd = shm_open( SHM_ID_MAC2TAP, O_RDWR , 0600 );
    if ( fd < 0) {perror("Shared memory error:"); exit(-1);}

    // create shared memory area
    mac2tap = (RingBuffer_t*)mmap( 0, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0 );
    close( fd );

    // initialize our sequence numbers in the ring buffer
    tap2mac->_wseq = tap2mac->_rseq = 0;
    mac2tap->_wseq = mac2tap->_rseq = 0;

    tss.tv_sec = 0;
    tss.tv_nsec = SLEEP_NANOS;
    return (0);
}

unsigned short checksum(unsigned char *buffer, int count)
{
	register long sum = 0;
	while( count > 1 ) {
		//This is the inner loop 
		sum +=  *(unsigned short *) buffer++;
		count -= 2;
	}		
	//Add left-over byte, if any 
	if( count > 0 )
		sum += * (unsigned char *) buffer;
	//Fold 32-bit sum to 16 bits 
 	while (sum>>16)
	sum = (sum & 0xffff) + (sum >> 16);
	return ~sum;
}

unsigned char data[] =
  {
    0x00, 0x0A, 0xE6, 0xF0, 0x05, 0xA3, 0x00, 0x12,
    0x34, 0x56, 0x78, 0x90, 0x08, 0x00, 0x45, 0x00,
    0x00, 0x30, 0xB3, 0xFE, 0x00, 0x00, 0x80, 0x11,
    0x72, 0xBA, 0x0A, 0x00, 0x00, 0x03, 0x0A, 0x00,
    0x00, 0x02, 0x04, 0x00, 0x04, 0x00, 0x00, 0x1C,
    0x89, 0x4D, 0x00, 0x01, 0x02, 0x03, 0x04, 0x05,
    0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D,
    0x0E, 0x0F, 0x10, 0x11, 0x12, 0x13
  };

unsigned int crc_table[] =
  {
    0x4DBDF21C, 0x500AE278, 0x76D3D2D4, 0x6B64C2B0,
    0x3B61B38C, 0x26D6A3E8, 0x000F9344, 0x1DB88320,
    0xA005713C, 0xBDB26158, 0x9B6B51F4, 0x86DC4190,
    0xD6D930AC, 0xCB6E20C8, 0xEDB71064, 0xF0000000
  };

unsigned int do_crc(int len, unsigned char *data) {

  unsigned int n, crc=0;

  for (n=0; n<len; n++) {
    crc = (crc >> 4) ^ crc_table[(crc ^ (data[n] >> 0)) & 0x0F];  /* lower nibble */
    crc = (crc >> 4) ^ crc_table[(crc ^ (data[n] >> 4)) & 0x0F];  /* upper nibble */
  }
  /* display the CRC, lower byte first */
/*
  for (n=0; n<4; n++) {
    printf("%02X ", crc & 0xFF);
    crc >>= 8;
  }
  printf("\n");
*/
  return crc;
}

/**************************************************************************
** cread: read routine that checks for errors and exits if an error is    *
**        returned.                                                       *
***************************************************************************/
int cread(int fd, char *buf, int n){

  int nread;

  nread=read(fd, buf, n);
  if(nread < 0 && errno !=EAGAIN){
    perror("Reading data");
    exit(1);
  } else if (nread < 1)
       nread = 0;
  return nread;
}

/**************************************************************************
** cwrite: write routine that checks for errors and exits if an error is  *
**         returned.                                                      *
***************************************************************************/
int cwrite(int fd, char *buf, int n){

  int nwrite;

  if((nwrite=write(fd, buf, n)) < 0){
    perror("Writing data");
    exit(1);
  }
  return nwrite;
}

/**************************************************************************
*** read_n: ensures we read exactly n bytes, and puts them into "buf".     *
***         (unless EOF, of course)                                        *
****************************************************************************/
int read_n(int fd, char *buf, int n) {

  int nread, left = n;

  while(left > 0) {
    if ((nread = cread(fd, buf, left)) == 0){
      return 0 ;
    }else {
      left -= nread;
      buf += nread;
    }
  }
  return n;
}


#define CRC_LEN 4
#define MIN_PAYLOAD (64-8)
#define BYTES_LANES 8

void dump_to_xgmii(char *buf, int frame_len)
{
        unsigned long long * llp;
        unsigned char ctrl = 0x00;
        unsigned char rem;
        int frame_len_aligned;

        // compute a new frame length 64bit aligned
        rem = frame_len % BYTES_LANES;
        frame_len_aligned = frame_len + BYTES_LANES - rem;
        // set end of frame
        buf[frame_len] = 0xFD;
        // fill the rest of the 64bit word with idles
        for (int i=frame_len+1 ; i < frame_len_aligned; i++) { buf[i] = 0x07;} 
        // compute ctrl code for last 64bit word
        for (int i=rem ; i< BYTES_LANES ; i++) { ctrl |= 0x1 << i; };


        // preamble & start of packet
        xgmii_write(XGMII_PREAMBLE, 0x01);

        // send packet % 64bit
        for (int i = 0; i < frame_len_aligned; i+=8) {
                llp = (unsigned long long *) (buf+i);
                if(i+8 == frame_len_aligned) xgmii_write(*llp,ctrl); //last word
                else  xgmii_write(*llp,0x0);
        }

        xgmii_idle();
}

/*
* tap2mac ring buffer full
*/
int tap2mac_empty()
{
        if( tap2mac->_wseq%NUM_PACKETS == tap2mac->_rseq%NUM_PACKETS )
             return 1;
        else
             return 0;
}

void tap2xgmii(int *ret)
{
	unsigned char *buf;
	unsigned long crc;
	int cnt, i, frame_len=0;
     
        if(tap2mac_empty()) { // no candidate packets - send idle pattern
               *ret = 0; 
		xgmii_idle();
		goto out; 
                }
         else {
                frame_len = tap2mac->_buffer[tap2mac->_rseq].len;
                buf = (unsigned char *)tap2mac->_buffer[tap2mac->_rseq].data;
                // move ptr to next pkt
                tap2mac->_rseq = (tap2mac->_rseq +1) % NUM_PACKETS;
         } 

	 /* ethernet FCS */
	 frame_len += 4;    

	 // minimum frame length = 64
	 // preamble length =8 
	 // crc length =4 
	 if (frame_len < MIN_PAYLOAD) { // zero padding
            for (i= frame_len; i < MIN_PAYLOAD; i++){ 
	 	buf[i]=0;	
		frame_len++;
	    }
	 }
         crc = do_crc(frame_len-4,buf);
	 //printf("frame length %d\n",frame_len);
	 buf[frame_len-1]= (char) ((crc & 0xff000000) >>24);
	 buf[frame_len-2]= (char) ((crc & 0x00ff0000) >>16);
	 buf[frame_len-3]= (char) ((crc & 0x0000ff00) >>8);
	 buf[frame_len-4]= (char) (crc & 0x000000ff);

	 /* send  packet data to XGMII port */
         dump_to_xgmii(buf, frame_len);

	 *ret = 1;

out:
	 return ;
}
//static long id = 0;
//static unsigned int rx_frame_len = 0;
//static unsigned char rx_tmp_pkt[MAX_PACKET_SIZE] = {0};
long id = 0;
unsigned int rx_frame_len = 0;
unsigned char rx_tmp_pkt[MAX_PACKET_SIZE] = {0};

/*
* mac2tap ring buffer full
*/
int mac2tap_full()
{
        if( (mac2tap->_wseq+1)%NUM_PACKETS == mac2tap->_rseq%NUM_PACKETS )
             return 1;
        else
             return 0;
}

inline void gmii2pipe(unsigned int frame_len)
{
        unsigned char * buf;

	// drop ethernet FCS
	frame_len -= 4;

        if(!mac2tap_full()) { 
            buf = (unsigned char *) mac2tap->_buffer[mac2tap->_wseq].data;
            memcpy(buf, rx_tmp_pkt+7, frame_len-7); //cut the ethernet preamble out
            mac2tap->_buffer[mac2tap->_wseq].len = frame_len-7;
            mac2tap->_buffer[mac2tap->_wseq].id = id++;

            mac2tap->_wseq = (mac2tap->_wseq +1) % NUM_PACKETS;
        } else printf("mac2tap ring buffer full : dropping packet\n");

}

//static int packet_found = 0; 
int packet_found = 0; 

inline int parse_data( unsigned long long data, unsigned char control)
{
    for (int i = 0; i < 8 ; i++) {
        unsigned char *o = ((unsigned char *) &data) + i;
        unsigned char ctrl = (control >> i) & 0x01;
 
        if (ctrl && (*o == 0xFB)) { packet_found = 1;}

        if (packet_found) {
             if (ctrl && (*o == 0xFD)) {packet_found = 0; return 0;}
             if ( !ctrl ) rx_tmp_pkt[rx_frame_len++] = *o;
        }
    }
    return 1;
}


inline int xgmii_read(long long  xgmiiTxd, char xgmiiTxc)
{
	int ret;
        unsigned long long xgmii_data;
        unsigned char ctrl;
        int parse_data_flag;

	xgmii_data = (unsigned long long ) xgmiiTxd;
        ctrl = (unsigned char) xgmiiTxc;
        
        parse_data_flag = parse_data(xgmii_data, ctrl);

        if(!parse_data_flag) {
		// emit a packet
		gmii2pipe(rx_frame_len);
                rx_frame_len = 0;
        };

out:
	return 0;
}

