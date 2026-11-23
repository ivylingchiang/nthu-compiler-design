uint32_t ext_dsp_codegen(uint32_t a, uint32_t b);
/* Operand order: uksub8 and ucmplt8 are not commutative, so swapped operands change the result */
uint32_t ext_dsp_codegen(uint32_t a, uint32_t b) {
	return __rv__uksub8(a, __rv__ucmplt8(a, b));
}
