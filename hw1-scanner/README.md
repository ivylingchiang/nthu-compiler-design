# HW1: Lexical Analyzer

This is a Flex scanner for a subset of C. It prints every token with its category. After each source line, it prints the line number and the line's text. Two pragmas turn parts of this output on or off.

```sh
make scanner
./scanner < input.c
make test        # runs every case in tests/
```

## Output format

```
$ printf "char a = 'i';\n" | ./scanner
#key:char
#id:a
#op:=
#char:'i'
#punc:;
1:char a = 'i';
```


| Category                                 | Examples                                       |
| ------------------------------------------ | ------------------------------------------------ |
| `#key`                                   | `int`, `const`, `for`, `return`, `switch`, ... |
| `#macro`                                 | `NULL`, `__LINE__`, `INT_MAX`, `MIN`, ...      |
| `#id`                                    | identifiers                                    |
| `#op`                                    | `+ - * / % ++ -- < <= == != = && \|\| ! & \|`     |
| `#punc`                                  | `: ; , . [ ] ( ) { }`                          |
| `#integer`, `#float`, `#char`, `#string` | literals, including escape sequences           |

- Comments (`//` and `/* ... */`) produce no tokens. They appear only in the printed source line.
- `#pragma source on|off` turns the `<line>:<text>` output on or off.
- `#pragma token on|off` turns the `#<category>:<text>` output on or off.

## Grading criteria

From the course spec. The total is 100 points.


| Item                                                   | Points | Test               | Status |
| -------------------------------------------------------- | -------- | -------------------- | -------- |
| Keywords and identifiers                               | 10     | `01_keyword_id`    | ✅     |
| Macros                                                 | 10     | `02_macro`         | ✅     |
| Operators and punctuation                              | 15     | `03_op_punc`       | ✅     |
| Integers, floating-point numbers, characters           | 15     | `04_number_char`   | ✅     |
| Strings (with escape sequences)                        | 15     | `05_string`        | ✅     |
| Comments (single-line and multi-line)                  | 15     | `06_comment`       | ✅     |
| Pragma directives                                      | 10     | `07_pragma`        | ✅     |
| Comprehensive test (last line has no trailing newline) | 10     | `08_comprehensive` | ✅     |

The spec also applies these penalties to all assignments:


| Penalty                            | Points                      | Status                                     |
| ------------------------------------ | ----------------------------- | -------------------------------------------- |
| Any compiler warning               | −20                        | 0 warnings with GNU gcc, also with `-Wall` |
| Late submission                    | −10 per day                | —                                         |
| Runs, but does not follow the spec | 20% off after manual review | —                                         |

## Edge cases handled

These cases are easy to get wrong in a scanner. Each one has a test.

- **Pragma and line numbers:** a pragma pattern that ends in `\n` also consumes the newline, which shifts every line number after it. The pragma rules are anchored with `^` and leave the newline to the newline rule.
- **Escape sequences in strings:** a simple `"[^"\n]*"` pattern stops at an escaped quote (`\"`). The string pattern `\"(\\.|[^"\\\n])*\"` accepts any escape sequence, so `"a\"b\nc"` is a single `#string` token.
- **Patterns inside comments:** with an inclusive start condition (`%s`), other rules still match inside a comment, so `/*"abc*/` looks like an unterminated string. The comment state is exclusive (`%x`).
- **Last line without a newline:** if a line prints only when its `\n` is scanned, the last line of the file can be lost. An `<<EOF>>` rule prints it.
- **Zero warnings:** `%option noyywrap nounput noinput` removes the unused-function warnings in Flex's generated code, and no `-lfl` link is needed.
- **One place for line tracking:** `YY_USER_ACTION` adds the matched text to the current line, and each rule calls `emit("<category>")`. No token-number table or range check is needed.

## Assumptions

The TA's `golden_scanner` is no longer available, so I based these behaviors on the spec:

- A string literal is one token, from the opening quote to the closing quote.
- `a-1` is scanned as `#id:a`, `#integer:-1`, because Flex uses the longest match.
- A last line without a trailing newline is still printed with its line number.

## Files

- [scanner.l](scanner.l): the scanner
- [tests/](tests/): input `*.c` and expected output `*.expected` for each test
- [spec/HW1_Spec.pdf](spec/HW1_Spec.pdf): the assignment spec (pages 37–53 are the requirements)
- [report/HW1_Implementation_Report.pdf](report/HW1_Implementation_Report.pdf): implementation report: how the code implements each requirement
