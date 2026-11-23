uint32_t ext_dsp_codegen(uint32_t a, uint32_t b);
uint32_t ext_dsp_codegen(uint32_t a, uint32_t b) {
	uint32_t s = __rv__uksub8(a, b);
	uint32_t e = __rv__cmpeq8(a, b);
	return __rv__ukadd8(s, e);
}
