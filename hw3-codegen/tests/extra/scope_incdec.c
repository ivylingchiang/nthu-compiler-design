void codegen();
/* Block scope and shadowing, values of prefix/postfix ++ --, chained assignment */
void codegen() {
  int x = 1;
  {
    int x = 2;
    { int x = 3; delay(x); }
    delay(x);
  }
  delay(x);
  int i = 5;
  delay(i++);
  delay(i);
  delay(++i);
  delay(i--);
  delay(--i);
  int a, b, c;
  a = b = c = 9;
  delay(a + b + c);
  digitalWrite(i, HIGH);
}
