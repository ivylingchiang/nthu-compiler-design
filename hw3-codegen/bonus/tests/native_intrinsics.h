/* For host gcc expected output: map the __rv__* intrinsics to the C reference implementation */
#include "pext_ref.h"
#define __rv__ukadd8  ref_ukadd8
#define __rv__uksub8  ref_uksub8
#define __rv__cmpeq8  ref_cmpeq8
#define __rv__ucmplt8 ref_ucmplt8
