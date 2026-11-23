/* For host gcc expected output: provides the Arduino API and main, matching spike-sample/main.c */
#include <stdio.h>
#include <stdint.h>
#define HIGH 1
#define LOW 0
static void digitalWrite(int pin, int value) { printf("Arduino digitalWrite(%d, %d);\n", pin, value); }
static void delay(int ms) { printf("Arduino delay(%d);\n", ms); }
void codegen();
int main(void) { codegen(); return 0; }
