/*
 * C reference implementation of Andes P-extension 8-bit SIMD instructions (semantics per riscv-p-spec)
 * A 32-bit register is treated as 4 independent uint8 lanes.
 *
 *   UKADD8   unsigned saturating add: min(a + b, 255)
 *   UKSUB8   unsigned saturating subtract: max(a - b, 0)
 *   CMPEQ8   a == b ? 0xFF : 0x00
 *   UCMPLT8  a <  b ? 0xFF : 0x00 (unsigned compare)
 */
#ifndef PEXT_REF_H
#define PEXT_REF_H
#include <stdint.h>

static inline uint32_t pext_lanes(uint32_t a, uint32_t b, int op) {
    uint32_t r = 0;
    for (int i = 0; i < 4; i++) {
        uint32_t x = (a >> (8 * i)) & 0xFF, y = (b >> (8 * i)) & 0xFF, z = 0;
        switch (op) {
        case 0: z = (x + y > 0xFF) ? 0xFF : x + y; break;   /* ukadd8 */
        case 1: z = (x < y) ? 0 : x - y; break;              /* uksub8 */
        case 2: z = (x == y) ? 0xFF : 0; break;              /* cmpeq8 */
        case 3: z = (x < y) ? 0xFF : 0; break;               /* ucmplt8 */
        }
        r |= z << (8 * i);
    }
    return r;
}

static inline uint32_t ref_ukadd8(uint32_t a, uint32_t b)  { return pext_lanes(a, b, 0); }
static inline uint32_t ref_uksub8(uint32_t a, uint32_t b)  { return pext_lanes(a, b, 1); }
static inline uint32_t ref_cmpeq8(uint32_t a, uint32_t b)  { return pext_lanes(a, b, 2); }
static inline uint32_t ref_ucmplt8(uint32_t a, uint32_t b) { return pext_lanes(a, b, 3); }

#endif
