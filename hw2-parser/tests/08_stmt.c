int main() {
  int i;
  /* multi
     line */
  if (i) { i = 1; } else { }
  while (i < 10) i++;
  do { i--; } while (i);
  for (i = 0; i < 3; i++) { continue; }
  for (;;) break;
  switch (i) {
    case 1:
    case 2: i = 2; break;
    default:
  }
  switch (i) { }
  { int j; j = i; }
  return;
  return i;
}
