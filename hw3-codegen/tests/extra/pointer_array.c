void codegen();
int total(int *arr, int n);
int g = 7;
int garr[4] = {10, 20, 30, 40};

/* Pointer ++/--, pointer subtraction, &arr[i], array initializers, global variables and arrays */
void codegen() {
  int a[5] = {5, 4, 3, 2, 1};
  int *p = a;
  p++;
  delay(*p);
  p = p + 2;
  delay(*p);
  delay(p - a);
  int *q = &a[4];
  delay(q - p);
  --q;
  delay(*q);
  delay(*(a + 1) + a[3]);
  delay(total(a, 5));
  delay(total(garr, 4));
  g = g * 3;
  garr[2] = g;
  delay(garr[2] + g);
  int *gp = &g;
  *gp = *gp + 1;
  digitalWrite(g, LOW);
}

int total(int *arr, int n) {
  int i, s = 0;
  for (i = 0; i < n; i++) { s = s + arr[i]; }
  return s;
}
