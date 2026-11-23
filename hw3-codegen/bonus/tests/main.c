/*
 * Test driver: calls ext_dsp_codegen(a, b) on a set of inputs and prints the results.
 * The same file is used in two places:
 *   - host gcc + C reference implementation -> expected output
 *   - RV32 Spike + assembly from codegen   -> actual output
 * Inputs include the spec examples (65280, 65283) and (100, 200), plus per-lane saturation and equality edge cases.
 */
#include <stdio.h>
#include <stdint.h>

uint32_t ext_dsp_codegen(uint32_t a, uint32_t b) __asm__("ext_dsp_codegen");

static const uint32_t inputs[][2] = {
    { 65280u, 65283u },             /* spec example */
    { 100u, 200u },                 /* spec example */
    { 0u, 0u },
    { 0xFFFFFFFFu, 0xFFFFFFFFu },
    { 0xFFFFFFFFu, 0u },
    { 0u, 0xFFFFFFFFu },
    { 0x80808080u, 0x80808080u },   /* add saturates exactly */
    { 0x7F7F7F7Fu, 0x80808080u },   /* add just avoids overflow */
    { 0x01FF7F80u, 0x02018081u },   /* each lane differs */
    { 0x10203040u, 0x40302010u },   /* lane order reversed */
    { 0x12345678u, 0x12345678u },
    { 0xDEADBEEFu, 0x0BADF00Du },
};

int main(void) {
    for (unsigned i = 0; i < sizeof inputs / sizeof inputs[0]; i++) {
        uint32_t a = inputs[i][0], b = inputs[i][1];
        printf("ext_dsp_codegen(0x%08lx, 0x%08lx) = 0x%08lx\n",
               (unsigned long)a, (unsigned long)b, (unsigned long)ext_dsp_codegen(a, b));
    }
    return 0;
}
