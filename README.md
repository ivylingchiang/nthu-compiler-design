# C-Subset Compiler to RISC-V (Flex + Yacc)

[![CI](https://github.com/ivylingchiang/nthu-compiler-design/actions/workflows/ci.yml/badge.svg)](https://github.com/ivylingchiang/nthu-compiler-design/actions/workflows/ci.yml)

A compiler for a subset of C that emits RISC-V assembly. It is built with Flex and Yacc, one stage at a time, as the three programming assignments of **CS340400 Compiler Design** at National Tsing Hua University (Spring 2025, Prof. Jenq-Kuen Lee).

```
C source ──► HW1 Scanner ──► tokens ──► HW2 Parser ──► syntax tree ──► HW3 Codegen ──► RISC-V assembly
             (Flex)                     (Yacc, LALR(1))                (AST walk)      (RV64 / RV32)
```

The generated assembly runs on the [Spike](https://github.com/riscv-software-src/riscv-isa-sim) RISC-V simulator. With the `--rv32` flag, it targets an Andes Corvette-F1 board and can use P-extension SIMD instructions.

## Status

| Assignment | Topic | Tests | Details |
|---|---|---|---|
| [HW1](hw1-scanner/) | Lexical analyzer: tokens, comments, `#pragma` | 8/8 | 0 compiler warnings |
| [HW2](hw2-parser/) | Syntax analyzer: prints the syntax tree as XML | 9/9 | 0 Yacc conflicts, 0 warnings |
| [HW3](hw3-codegen/) | Code generator: RISC-V 64-bit assembly on Spike | 15/15 on RV64, 15/15 on RV32 | 9 public tests + 6 of my own |
| [HW3 Bonus](hw3-codegen/#hw3-bonus-andes-p-extension-intrinsics) | RV32 target and Andes P-extension SIMD intrinsics | 5/5 (emulated) | Not yet tested on the physical board |

## Build and test

Each assignment builds with the same commands the grader used:

```sh
cd hw1-scanner && make scanner && ./scanner < input.c
cd hw2-parser  && make parser  && ./parser  < input.c
cd hw3-codegen && make codegen && ./codegen < input.c   # writes codegen.S
```

Each assignment also has a `make test` target.

**Requirements:** `flex`, `byacc` (the grader uses byacc), and `gcc`. HW3 also needs `riscv64-unknown-elf-gcc`, `spike` and `pk`.

### Docker environment

The easiest way to get the RISC-V toolchain and Spike is the Docker image in [dev/docker/](dev/docker/). It is based on Ubuntu 24.04 and includes gcc, flex, byacc, the xPack RISC-V GCC, Spike, and `pk` for both RV64 and RV32. Spike and `pk` are pinned to fixed commits. The `toolchain` stage has everything needed to build and test. The default stage also adds LaTeX for building the implementation reports.

[GitHub Actions](.github/workflows/ci.yml) builds the same image and runs every test on each push.

```sh
docker build --target toolchain -t nthu-compiler:latest dev/docker
docker run --rm -v "$PWD":/work -w /work nthu-compiler:latest make -C hw3-codegen test-all
```

The helper script [dev/run.sh](dev/run.sh) wraps these commands. By default, it uses a Colima Docker context named `colima-compiler`. To use your normal Docker setup instead, set `COMPILER_DOCKER_CONTEXT=default`:

```sh
COMPILER_DOCKER_CONTEXT=default dev/run.sh --build
COMPILER_DOCKER_CONTEXT=default dev/run.sh make -C hw3-codegen test-all
```

## Repository layout

```
.
├── hw1-scanner/      scanner.l, makefile, tests/, spec/, report/
├── hw2-parser/       scanner.l, parser.y, makefile, tests/, spec/, report/
├── hw3-codegen/      scanner.l, parser.y, makefile, tests/, spec/, report/
│   ├── testcases/    public test cases from the TAs
│   ├── spike-sample/ Spike sample project from the TAs (main.c + codegen.S)
│   └── bonus/        HW3 Bonus spec, test cases, test harness, Arduino sample
├── slides/           lecture slides
└── dev/              development notes, plans and Docker environment (in Chinese)
```

The grader accepted only `scanner.l`, `parser.y` and `makefile`. Because of this, all of the C code for each stage, including the AST, the symbol table and the code generator, lives inside those files.

## What I learned

**Lexical analysis (HW1)**
- Writing token rules as regular expressions, and how Flex's longest-match and first-rule-wins rules decide between overlapping patterns.
- Using exclusive start conditions (`%x`) for multi-line comments. My original inclusive (`%s`) version let other rules match inside comments.
- Tracking line content with `YY_USER_ACTION` and handling a last line that has no trailing newline with `<<EOF>>`.

**Parsing (HW2)**
- Designing an LALR(1) grammar for C declarations, expressions and statements with zero shift/reduce and reduce/reduce conflicts.
- Encoding operator precedence and associativity with `%left`, `%right` and `%prec`, instead of using one grammar level per precedence tier.
- Factoring the grammar so one token of lookahead after `type ID` is enough to choose between a variable, a function declaration and a function definition.
- Passing semantic values between Flex and Yacc through `yylval` and `%union`.

**Code generation (HW3)**
- Building an AST in the parser actions and generating code in a separate pass. Then the frame size is known before the prologue is emitted, and loop labels for `break` and `continue` are easy to manage.
- Using a scoped symbol table with block-level shadowing.
- Following the RISC-V calling convention: arguments in `a0` to `a7`, return value in `a0`, saving `ra` and `s0`, and keeping `sp` 16-byte aligned.
- Evaluating expressions with a stack machine, scaling pointer arithmetic, and taking the address of lvalues (`&x`, `*p`, `a[i]`).
- Compiling control flow to branches: short-circuit `&&` and `||`, `switch` fall-through, and avoiding the ±4 KB range limit of conditional branches.
- Retargeting one code generator to RV64 and RV32 with a word-size parameter, and choosing unsigned instructions (`sltu`, `divu`, `srl`) based on operand types.
- Lowering compiler intrinsics directly to SIMD instructions (`ukadd8`, `cmpeq8`, and others).

**Testing and tooling**
- Differential testing: I compiled the same C program with host `gcc` and used its output as the expected result for my compiler on Spike.
- Testing without the target hardware: I emulated the P-extension instructions in C. Then I ran mutation tests (swapped operands, signed instead of unsigned) to confirm that the tests catch real mistakes.
- Building a reproducible cross-compilation environment in Docker, including building Spike and `pk` from source.

## Acknowledgements

- Course materials (specs, lecture slides, public test cases, and Spike and Arduino sample projects) are by Prof. Jenq-Kuen Lee and the CS340400 teaching assistants. They are included here for reference and belong to their authors.
- When I first took the course, I looked at GitHub repositories from earlier students of the same course for ideas on how to structure the scanner and parser. The code in this repository is my own implementation.

## License

My code is available under the [MIT License](LICENSE). The license does not cover the course materials listed in [Acknowledgements](#acknowledgements).
