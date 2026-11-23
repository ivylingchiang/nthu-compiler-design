# HW2 Parser 設計筆記

規格：[hw2-parser/spec/HW2_Spec.pdf](../hw2-parser/spec/HW2_Spec.pdf)（第 30–50 頁是需求）
程式：[scanner.l](../hw2-parser/scanner.l)、[parser.y](../hw2-parser/parser.y)、[makefile](../hw2-parser/makefile)

## 配分對照

| 項目 | 配分 | 測資 | 狀態 |
|---|---|---|---|
| Scalar Declarations without initialization | 10 | `01_scalar_decl` | ✅ |
| Array Declarations without initialization | 10 | `02_array_decl` | ✅ |
| Function Declarations | 10 | `03_func_decl` | ✅ |
| Expressions（一元、函式呼叫、陣列、指標、轉型） | 10 | `04_expr_unary` | ✅ |
| Expressions（算術、比較、邏輯） | 10 | `05_expr_arith` | ✅ |
| Expressions（全部運算子） | 10 | `06_expr_all` | ✅ |
| Full Implementation of Variable Declarations | 10 | `07_decl_init` | ✅ |
| Statements | 20 | `08_stmt` | ✅ |
| Function Definitions | 10 | `09_func_def` | ✅ |
| Yacc conflict 或編譯 warning | −20 | — | ✅ byacc 0 conflict、GNU gcc 0 warning |

## 容易出錯的地方：scanner.l

| # | 陷阱 | 影響 | 做法 |
|---|---|---|---|
| S1 | 沒有 `\n` 規則時，flex 預設會 ECHO 換行 | 輸出出現多餘換行，行號也不會增加 | 所有空白都有明確規則，換行只增加 `lineno` |
| S2 | `"/*"` 沒有進入註解狀態 | 註解內容被當成 token | 沿用 HW1 的 `%x COMMENT` |
| S3 | 沒有 `.` 的預設規則 | 未知字元被 ECHO，輸出被汙染 | 最後一條規則 `.` 回報錯誤 |
| S4 | `FLOAT` 帶有 `[+-]?` | `a-1.5` 被切成 `a`、`-1.5`，syntax error | 正負號交給 parser |
| S5 | 語意值直接指向 `yytext` | `yytext` 會被下一個 token 覆蓋，char 字面值輸出錯 | `tok()` 對每個值 `strdup` |
| S6 | 沒有處理 `NULL` | 規格要求 `NULL` 等於整數 `0` | scanner 直接回傳 `"0"` |
| S7 | 用到 `atoi`、`atof`、`strdup` 卻沒有 `#include <stdlib.h>` | warning，扣 20 分 | 加上 include |

## 容易出錯的地方：parser.y

| # | 陷阱 | 影響 | 做法 |
|---|---|---|---|
| P1 | 單字元 token 取名字（`L_BRACKET`、`L_PARENTHESIS`…），容易對錯字元 | `(expr)` 被印成 `{expr}` | 單字元 token 直接回傳字元，grammar 寫 `'('` |
| P2 | action 回傳 stack 上的 `buffer`（`$$ = buffer`） | undefined behavior，輸出亂碼 | `J(...)` 動態配置 |
| P3 | 每個 action 用固定大小的 `char buffer[1024]` 加 `sprintf` | 每層 `<expr>` 多 13 個字元，巢狀運算式會 overflow | `J(...)` 先算長度再 `malloc` |
| P4 | 純量、陣列、函式各用不同的型別非終端符號 | conflict；`const` 陣列、`const` 參數無法 parse | 全部使用同一個 `type_spec` |
| P5 | `switch` 把 case／default／語句的組合逐一列成規則 | 規則重疊產生 conflict | `switch_clauses` + `switch_clause` 兩條規則 |
| P6 | `%define parse.error verbose` 是 Bison 專屬語法 | 評分用的 byacc 無法編譯 | 只使用 POSIX yacc 的功能 |
| P7 | 漏掉 `*p = expr` 初始化、`(int *)x` 指標轉型 | 對應項目失敗 | 宣告子和一元運算都涵蓋 |
| P8 | `yyerror` 沒有 `exit(1)` | 錯誤之後繼續輸出 | 印出錯誤並 `exit(1)` |

## 設計

1. **單字元 token 直接回傳字元**：`return yytext[0]`，grammar 裡寫 `'('`，規則讀起來和 C 一樣。
2. **字串組合 helper**：`J(...)` 串接任意多個字串（最後一個參數是 `NULL`），先算總長度再 `malloc`；`EXPR(...)`、`STMT(...)` 巨集負責包 tag。
3. **統一宣告文法**：所有地方都用同一個 `type_spec`，讀完 `ID` 之後依下一個 token 分流，LALR(1) 能直接決定：
   ```
   declaration : type_spec ID '(' params ')' ';'          → func_decl
               | type_spec ID '(' params ')' compound      → func_def
               | type_spec '*' ID '(' ...                  → 指標回傳
               | type_spec init_declarators ';'            → scalar_decl / array_decl
   ```
   宣告子列表帶 `is_array` 旗標，只要有一個陣列，整條宣告就輸出成 `array_decl`。
4. **運算式**：全部放在同一個 `expr` 規則，用 `%left`、`%right`、`%prec` 處理優先權，依 [cppreference 的優先權表](https://en.cppreference.com/w/c/language/operator_precedence) 排列。前置運算子用 `%prec UNARY`，後置的 `++`、`--`、`[]`、`()` 放在最高優先權。函式呼叫和陣列存取只能接在 `ID` 後面，所以 `(` 和 `[` 不會產生 conflict。
5. **switch**：
   ```
   switch_clauses : /* empty */ | switch_clauses switch_clause ;
   switch_clause  : CASE expr ':' stmts_opt | DEFAULT ':' stmts_opt ;
   ```
6. **語意值全部是字串**：數字在 scanner 端就正規化（整數用 `%d`、浮點數用 `%f` 輸出），`NULL` 直接回傳 `"0"`。

## 依規格推斷的輸出格式

規格只寫「Follow `golden_parser` in the case of ambiguity」，但 golden 已經拿不到了。以下採用最常見的寫法，並在測資裡註明：

| 結構 | 採用的輸出 |
|---|---|
| `(a)` | `<expr>(<expr>a</expr>)</expr>` |
| `f(1)` | `<expr>f(<expr>1</expr>)</expr>` |
| `a[1]` | `<expr>a[<expr>1</expr>]</expr>` |
| `long long` | `longlong`（去除空白） |
| `'a'` | `<expr>'a'</expr>`（保留引號） |

## 測試

- `hw2-parser/tests/` 有 9 組測資，對應 9 個配分項目；`make test` 逐一比對 `*.expected`。
- `make scanner`、`make parser` 都能單獨執行（規格會分別執行）。
- 結果（2026-11-23）：9/9 通過；byacc 0 conflict；GNU gcc 0 warning（`-Wall` 也是）。`bison -y` 建置也是 9/9。助教的 9 個 HW3 測資也都能成功 parse。
