#include <stdlib.h>
#include <stdio.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>
#include <string.h>

#define SHM_ID_TAP2MAC "/tap2mac"
#define SHM_ID_MAC2TAP "/mac2tap"
#define MAX_PACKET_SIZE 9600
#define NUM_PACKETS 128
#define SLEEP_NANOS 1000   // 1 micro

typedef struct
{
    long            id;
    unsigned short  len;
    unsigned char   data[MAX_PACKET_SIZE];
} packet_t;

typedef  struct
{
    unsigned int _rseq;
    char _pad1[64];

    unsigned int _wseq;
    char _pad2[64];

    packet_t _buffer[NUM_PACKETS];
} RingBuffer_t;
