/*
 * Runtime support for `codegen --pext-emulate`: the generated assembly calls __pext_<op>(rs1, rs2),
 * and this file provides them from the C reference, so the program runs on a Spike without the P-extension.
 */
#include "pext_ref.h"
uint32_t __pext_ukadd8(uint32_t a, uint32_t b)  { return ref_ukadd8(a, b); }
uint32_t __pext_uksub8(uint32_t a, uint32_t b)  { return ref_uksub8(a, b); }
uint32_t __pext_cmpeq8(uint32_t a, uint32_t b)  { return ref_cmpeq8(a, b); }
uint32_t __pext_ucmplt8(uint32_t a, uint32_t b) { return ref_ucmplt8(a, b); }
