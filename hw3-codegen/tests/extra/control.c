void codegen();
/* for/continue/break, nested if-else, while/break, do-while/continue, switch fall-through */
void codegen() {
  int i, sum = 0;
  for (i = 0; i < 10; i = i + 1) {
    if (i % 2 == 0) { continue; }
    if (i > 7) { break; }
    sum = sum + i;
  }
  delay(sum);
  i = 0;
  while (1) { i = i + 3; if (i > 20) { break; } }
  delay(i);
  int k = 0, odd = 0;
  do { k = k + 1; if (k % 2 == 0) { continue; } odd = odd + 1; } while (k < 9);
  delay(odd);
  for (i = 0; i < 5; i++) {
    switch (i) {
      case 0: delay(100);
      case 1: delay(101); break;
      case 3: delay(103);
      default: delay(999);
    }
  }
  int x = 5;
  if (x < 3) { delay(1); } else { if (x < 6) { delay(2); } else { delay(3); } }
  for (;;) { x--; if (x == 0) { break; } }
  digitalWrite(x, HIGH);
}
