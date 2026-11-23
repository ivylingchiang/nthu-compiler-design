scanner: lex.yy.c
	gcc lex.yy.c -o scanner
lex.yy.c: scanner.l
	flex scanner.l

# Run each tests/*.c and compare with *.expected; on failure, write the diff to tests/*.diff
test: scanner
	@pass=0; fail=0; \
	for t in tests/*.c; do \
		exp=$${t%.c}.expected; \
		if ./scanner < $$t 2>&1 | cmp -s - $$exp; then \
			pass=$$((pass+1)); echo "PASS $$t"; \
		else \
			./scanner < $$t 2>&1 | diff -u $$exp - > $${t%.c}.diff; \
			fail=$$((fail+1)); echo "FAIL $$t  (see $${t%.c}.diff)"; \
		fi; \
	done; \
	echo "$$pass passed, $$fail failed"; [ $$fail -eq 0 ]

clean:
	rm -f scanner lex.yy.c tests/*.diff

.PHONY: test clean
