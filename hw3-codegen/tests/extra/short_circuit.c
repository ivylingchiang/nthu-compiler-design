void codegen();
int bump(int v);
int count = 0;

/* && / || must short-circuit: bump() must not run when the right side is skipped */
void codegen() {
  int r;
  r = 0 && bump(1);
  delay(r); delay(count);
  r = 1 || bump(1);
  delay(r); delay(count);
  r = 1 && bump(5);
  delay(r); delay(count);
  r = 0 || bump(0);
  delay(r); delay(count);
  digitalWrite(count, HIGH);
}

int bump(int v) { count = count + 1; return v; }
