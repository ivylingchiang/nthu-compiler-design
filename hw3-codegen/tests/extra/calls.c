void codegen();
int sum6(int a, int b, int c, int d, int e, int f);
int fact(int n);
void swap(int *p, int *q);
int *pick(int *p, int *q, int first);
int add(int a, int b);

void codegen() {
  delay(sum6(1, 2, 3, 4, 5, 6));
  delay(sum6(add(1, 2), add(add(3, 4), 5), 6, add(7, 8), 9, fact(5)));
  delay(fact(10));
  int x = 3, y = 40;
  swap(&x, &y);
  delay(x); delay(y);
  *pick(&x, &y, 1) = 77;
  delay(x);
  delay(*pick(&x, &y, 0) + 1);
  digitalWrite(add(20, 6), HIGH);
}

int sum6(int a, int b, int c, int d, int e, int f) { return a * 100000 + b * 10000 + c * 1000 + d * 100 + e * 10 + f; }
int fact(int n) { if (n <= 1) { return 1; } return n * fact(n - 1); }
void swap(int *p, int *q) { int t = *p; *p = *q; *q = t; }
int *pick(int *p, int *q, int first) { if (first) { return p; } return q; }
int add(int a, int b) { return a + b; }
