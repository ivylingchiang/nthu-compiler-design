YACC ?= yacc

all: parser

# The grader runs "make scanner" and "make parser"
scanner: lex.yy.c y.tab.h
	gcc -c lex.yy.c -o lex.yy.o

parser: lex.yy.c y.tab.c y.tab.h
	gcc -o parser lex.yy.c y.tab.c

lex.yy.c: scanner.l y.tab.h
	flex scanner.l

y.tab.c y.tab.h: parser.y
	$(YACC) -d -v parser.y

# Run each tests/*.c and compare with *.expected; on failure, write the diff to tests/*.diff
test: parser
	@pass=0; fail=0; \
	for t in tests/*.c; do \
		exp=$${t%.c}.expected; \
		if ./parser < $$t 2>&1 | cmp -s - $$exp; then \
			pass=$$((pass+1)); echo "PASS $$t"; \
		else \
			./parser < $$t 2>&1 | diff -u $$exp - > $${t%.c}.diff; \
			fail=$$((fail+1)); echo "FAIL $$t  (see $${t%.c}.diff)"; \
		fi; \
	done; \
	echo "$$pass passed, $$fail failed"; [ $$fail -eq 0 ]

clean:
	rm -f parser lex.yy.c lex.yy.o y.tab.c y.tab.h y.output tests/*.diff

.PHONY: all test clean
