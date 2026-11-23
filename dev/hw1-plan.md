# HW1 Scanner 設計筆記

規格：[hw1-scanner/spec/HW1_Spec.pdf](../hw1-scanner/spec/HW1_Spec.pdf)（第 37–53 頁是需求）
程式：[hw1-scanner/scanner.l](../hw1-scanner/scanner.l)

## 配分對照

| 項目 | 配分 | 測資 | 狀態 |
|---|---|---|---|
| Keywords && Identifiers | 10 | `01_keyword_id` | ✅ |
| Macros | 10 | `02_macro` | ✅ |
| Operators && Punctuations | 15 | `03_op_punc` | ✅ |
| Integers && Floating Points && Characters | 15 | `04_number_char` | ✅ |
| Strings | 15 | `05_string` | ✅ |
| Comments | 15 | `06_comment` | ✅ |
| Pragma Directives | 10 | `07_pragma` | ✅ |
| Comprehensive | 10 | `08_comprehensive` | ✅ |
| 編譯 warning | −20 | — | ✅ GNU gcc 0 warning（`-Wall`、`-Wextra` 也是） |

## 容易出錯的地方與處理方式

### 1. pragma 不能吃掉換行

如果 pragma 的 pattern 結尾是 `[ \t]*\n`，換行會被 pragma 規則吃掉，換行規則不會執行，行號和原始碼輸出就會錯位：

```
輸入                      錯誤的輸出
#pragma source on         #key:char ...
char a = 'i';             1:#pragma source on      ← 換行被併進行緩衝區
                          char a = 'i';            ← 第 2 行被當成第 1 行
```

**做法**：pragma 用 `^` 錨定在行首（允許前置空白），pattern 不包含 `\n`，換行一律交給換行規則處理。`source off` 那一行本身不印出（規格第 48 頁的範例沒有 `1:#pragma source off`），因為開關在換行之前就已經切換。

### 2. 字串內的跳脫序列

簡單的 `\042[^\042\n]*\042` 遇到 `"a\"b"` 會在 `\"` 提早結束。跳脫序列也不能把字串拆成多個 token：`"a\nb"` 要輸出成一個 `#string:"a\nb"`。

**做法**：`STRING` 是 `\"({ESCAPE}|\\.|[^"\\\n])*\"`，字元常數用同樣的寫法，但引號之間只能有一個元素。

### 3. 註解要用 exclusive start condition

`%s`（inclusive）的狀態下，其他規則在註解內仍然有效。例如 `/*"abc*/`：未結束字串的規則會比註解規則匹配得更長，導致誤報 error。

**做法**：`%x COMMENT`，註解內只有加上 `<COMMENT>` 前綴的規則有效；換行和行內容累積也在註解狀態下處理。

### 4. 最後一行沒有換行字元

只在遇到 `\n` 時才印出一行，檔案最後一行沒有換行時就會漏掉。

**做法**：`<INITIAL,COMMENT><<EOF>>` 規則在行緩衝區還有內容時印出，也涵蓋註解一路延伸到檔尾的情況。

### 5. 編譯 warning（評分會扣 20 分）

- `exit()` 需要 `#include <stdlib.h>`，否則 GNU gcc 會出現 implicit declaration warning。
- 不用 `while (token = yylex())` 這種寫法（`-Wall` 會警告），`main` 只呼叫一次 `yylex()`。
- `%option noyywrap nounput noinput`：不需要連結 `-lfl`，也不會產生沒用到的 `yyunput`、`input`。

### 6. 程式結構

- `YY_USER_ACTION` 在每條規則執行前把 `yytext` 加進行緩衝區，行內容只在一個地方累積。
- 每條規則直接呼叫 `emit("key")` 這類函式，種類就寫在 pattern 旁邊，不需要 token 編號表或數字範圍判斷。

## 測試

- `hw1-scanner/tests/` 有 8 組測資：7 個配分項目各一組，再加一組綜合測資（最後一行沒有換行字元）。
- `make test` 逐一執行並和 `*.expected` 比對，失敗時把 diff 寫進 `tests/*.diff`。
- 結果：8/8 通過（2026-11-23）。

## 依規格推斷的行為

助教的 `golden_scanner` 已經拿不到，以下行為是依規格推斷的：

- 字串整段輸出成一個 token。
- `a-1` 切成 `#id:a`、`#integer:-1`（flex 的 longest match）。規格第 41 頁只說明 `- 0` 和 `-0` 的差別。
- 最後一行沒有換行字元時仍然印出行號。
