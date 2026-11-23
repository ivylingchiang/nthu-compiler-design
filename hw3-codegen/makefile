YACC ?= yacc

# The grader runs "make codegen", then "./codegen < {testcase}"; output goes to codegen.S
codegen: lex.yy.c y.tab.c y.tab.h
	gcc -o codegen lex.yy.c y.tab.c

lex.yy.c: scanner.l y.tab.h
	flex scanner.l

y.tab.c y.tab.h: parser.y
	$(YACC) -d -v parser.y

# End-to-end tests (need riscv64-unknown-elf-gcc and spike; run inside the dev/run.sh container)
test: codegen
	@bash tests/run.sh

# HW3 Bonus: RV32 + P-extension intrinsics (no board needed; see bonus/tests/run.sh)
test-bonus: codegen
	@bash bonus/tests/run.sh

# All tests: RV64, RV32 and Bonus
test-all: codegen
	@bash tests/run.sh && TARGET=rv32 bash tests/run.sh && bash bonus/tests/run.sh

clean:
	rm -rf codegen lex.yy.c y.tab.c y.tab.h y.output codegen.S build

.PHONY: test test-bonus test-all clean
