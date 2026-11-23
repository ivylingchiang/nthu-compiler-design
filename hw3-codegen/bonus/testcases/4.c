uint32_t ext_dsp_codegen(uint32_t a, uint32_t b);
/* Mixed with ordinary ops: unsigned compare, unsigned divide, logical right shift (signed versions give different results) */
uint32_t ext_dsp_codegen(uint32_t a, uint32_t b) {
	uint32_t m = __rv__ucmplt8(a, b);
	uint32_t r = (a & m) | (b & ~m);
	if (a > b) {
		r = r + 4096;
	}
	return r / 3 + (a >> 28) + __rv__cmpeq8(r, r) % 7;
}
