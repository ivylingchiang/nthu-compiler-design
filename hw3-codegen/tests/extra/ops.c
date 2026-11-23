void codegen();
/* All arithmetic, bitwise, comparison and logical operators; division and modulo of negatives */
void codegen() {
  int a = 17, b = 5, n = -17;
  delay(a + b); delay(a - b); delay(a * b); delay(a / b); delay(a % b);
  delay(n / b); delay(n % b); delay(-a); delay(+b);
  delay(a & b); delay(a | b); delay(a ^ b); delay(~a); delay(a << 2); delay(n >> 1);
  delay(a < b); delay(a > b); delay(a <= 17); delay(a >= 18); delay(a == 17); delay(a != 17);
  delay(!a); delay(!0); delay(a && b); delay(a && 0); delay(0 || b); delay(0 || 0);
  delay((a + b) * (a - b) / 3 % 7);
  digitalWrite(13, a > b && b > 0);
}
