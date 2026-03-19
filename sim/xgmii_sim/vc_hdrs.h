#ifndef _VC_HDRS_H
#define _VC_HDRS_H

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif
#include <stdio.h>
#include <dlfcn.h>
#include "svdpi.h"

#ifdef __cplusplus
extern "C" {
#endif

#ifndef _VC_TYPES_
#define _VC_TYPES_
/* common definitions shared with DirectC.h */

typedef unsigned int U;
typedef unsigned char UB;
typedef unsigned char scalar;
typedef struct { U c; U d;} vec32;

#define scalar_0 0
#define scalar_1 1
#define scalar_z 2
#define scalar_x 3

extern long long int ConvUP2LLI(U* a);
extern void ConvLLI2UP(long long int a1, U* a2);
extern long long int GetLLIresult();
extern void StoreLLIresult(const unsigned int* data);
typedef struct VeriC_Descriptor *vc_handle;

#ifndef SV_3_COMPATIBILITY
#define SV_STRING const char*
#else
#define SV_STRING char*
#endif

#endif /* _VC_TYPES_ */


 extern int shared_mem_init();

 extern void tap2xgmii(/* OUTPUT */int *ret);
 
 extern void gmii2pipe(/* INPUT */unsigned int frame_len);
 
 extern int parse_data(/* INPUT */unsigned long long data, /* INPUT */unsigned char control);

 extern int xgmii_read(/* INPUT */long long xgmiiTxd, /* INPUT */char xgmiiTxc);

 extern void xgmii_write(/* INPUT */long long data, /* INPUT */char control);

 extern void xgmii_idle();

#ifdef __cplusplus
}
#endif


#endif //#ifndef _VC_HDRS_H

