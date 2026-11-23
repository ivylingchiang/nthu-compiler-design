# HW2: Syntax Analyzer

This is a Flex and Yacc parser for a subset of C. It reads declarations, expressions, statements and function definitions, and prints the syntax tree as XML-style tags (`<scalar_decl>`, `<array_decl>`, `<func_decl>`, `<func_def>`, `<expr>`, `<stmt>`). The scanner is the HW1 scanner, changed to return tokens to the parser instead of printing them.

```sh
make parser
./parser < input.c
make test        # runs every case in tests/
```

## Output format

The parser removes all whitespace inside tags, except inside char and string literals. The output has no newlines.

```
$ echo 'int a = 1 + 2 * 3;' | ./parser
<scalar_decl>inta=<expr><expr>1</expr>+<expr><expr>2</expr>*<expr>3</expr></expr></expr>;</scalar_decl>
```

## Grading criteria

From the course spec (page 49). The total is 100 points. The spec notes that items depend on each other, so the grading is not exact.


| Item                                                                                                                               | Points | Test             | Status |
| ------------------------------------------------------------------------------------------------------------------------------------ | -------- | ------------------ | -------- |
| Scalar declarations without initialization                                                                                         | 10     | `01_scalar_decl` | ✅     |
| Array declarations without initialization                                                                                          | 10     | `02_array_decl`  | ✅     |
| Function declarations                                                                                                              | 10     | `03_func_decl`   | ✅     |
| Expressions: arithmetic, `++`/`--`, unary `+`/`-`, `(expr)`, function calls, array subscripts, dereference, address-of, type casts | 10     | `04_expr_unary`  | ✅     |
| Expressions: arithmetic, comparison, logical operators                                                                             | 10     | `05_expr_arith`  | ✅     |
| Expressions: all operators                                                                                                         | 10     | `06_expr_all`    | ✅     |
| Variable declarations with initialization (scalar and array)                                                                       | 10     | `07_decl_init`   | ✅     |
| Statements                                                                                                                         | 20     | `08_stmt`        | ✅     |
| Function definitions                                                                                                               | 10     | `09_func_def`    | ✅     |


| Penalty                               | Points                                   | Status                                                       |
| --------------------------------------- | ------------------------------------------ | -------------------------------------------------------------- |
| Any Yacc conflict or compiler warning | −20                                     | 0 conflicts (byacc), 0 warnings (GNU gcc, also with `-Wall`) |
| Late submission                       | −10 per day                             | —                                                           |
| Runs, but does not follow the spec    | 20% off after manual review              | —                                                           |
| Does not run                          | flat 40 if code and report are submitted | —                                                           |

The parser also parses all 9 public HW3 test cases.

## Design

- **Semantic values are strings.** Every token and nonterminal carries its finished output text. A helper `J(...)` joins strings into heap memory, so there are no fixed-size buffers. The scanner also normalizes numbers: integers are printed with `%d`, floats with `%f`, and `NULL` becomes `0`.
- **Single-character tokens are characters.** The scanner returns `'('`, `'{'` and similar tokens as the character itself, so the grammar reads like C.
- **One declaration rule.** All declarations start with the same `type_spec`. After `type_spec ID`, the next token decides between a function declaration, a function definition and a variable declaration, and LALR(1) can decide it without conflicts. A flag on the declarator list chooses between `<scalar_decl>` and `<array_decl>`.
- **One expression rule.** All operators are alternatives of a single `expr` rule. Their precedence and associativity come from `%left`, `%right` and `%prec`, following the [C operator precedence table](https://en.cppreference.com/w/c/language/operator_precedence).
- **No dangling else.** The spec requires an `if` body to be a compound statement, so the grammar has no dangling-else ambiguity.

## Pitfalls avoided

- **Stray output from the scanner.** Flex copies any unmatched character, including `\n`, to stdout, and that corrupts the XML. The scanner has explicit rules for all whitespace and counts lines itself.
- **Confusing token names.** Single-character tokens are the characters themselves (`'('`, `'{'`, `'['`), so a grammar rule reads like the C it matches. Named tokens such as `L_PARENTHESIS` are easy to mix up.
- **Memory safety.** No action returns a stack buffer, and there is no fixed size limit. `J(...)` measures the result, allocates exactly enough memory, and joins the strings, so expressions can nest to any depth.
- **Zero conflicts.** Every declaration uses the same `type_spec` nonterminal, and `switch` uses only two clause rules (`case expr :` and `default :`, each followed by optional statements). byacc reports 0 shift/reduce and 0 reduce/reduce conflicts.
- **Portability.** The grammar uses only POSIX Yacc features. Both byacc, which the grader uses, and `bison -y` build it, and both pass all tests.

## Assumptions

The spec says to follow the TA's `golden_parser` when the spec is ambiguous. That program is no longer available, so I chose these formats:


| Input                                   | Output                                     |
| ----------------------------------------- | -------------------------------------------- |
| `(a)`                                   | `<expr>(<expr>a</expr>)</expr>`            |
| `f(1)`                                  | `<expr>f(<expr>1</expr>)</expr>`           |
| `a[1]`                                  | `<expr>a[<expr>1</expr>]</expr>`           |
| `long long`                             | `longlong`                                 |
| `'a'`                                   | `<expr>'a'</expr>` (quotes kept)           |
| The body of an `if` or a function       | `{...}` is not wrapped in another `<stmt>` |
| A declaration with any array declarator | the whole declaration is an `<array_decl>` |

## Files

- [scanner.l](scanner.l), [parser.y](parser.y): the scanner and the grammar
- [tests/](tests/): input `*.c` and expected output `*.expected`, one test per grading item
- [spec/HW2_Spec.pdf](spec/HW2_Spec.pdf): the assignment spec (pages 30–50 are the requirements)
- [report/HW2_Implementation_Report.pdf](report/HW2_Implementation_Report.pdf): implementation report: how the code implements each requirement
