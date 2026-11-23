uint32_t ext_dsp_codegen(uint32_t a, uint32_t b);
/* Nested calls: one intrinsic's result is passed straight into another */
uint32_t ext_dsp_codegen(uint32_t a, uint32_t b) {
	return __rv__ukadd8(__rv__uksub8(a, b), __rv__cmpeq8(a, __rv__ucmplt8(a, b)));
}
