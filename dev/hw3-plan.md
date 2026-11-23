# HW3 Code Generator 實作規劃

規格：[hw3-codegen/spec/HW3_Spec.pdf](../hw3-codegen/spec/HW3_Spec.pdf)、[Spike_UsageGuide.pdf](../hw3-codegen/spec/Spike_UsageGuide.pdf)
參考講義：[slides/chap4-YACC.with.riscv.2025.pdf](../slides/chap4-YACC.with.riscv.2025.pdf)（symbol table、scope、函式 prologue/epilogue）

## 目標

- parsing 和 code generation 分離：parser 只建 AST，codegen 另外走訪。
- 正確支援遞迴函式，stack frame 遵守 RISC-V calling convention。
- 同一份程式能切換 RV64／RV32（HW3 Bonus 需要）。

## 規格重點

- `make codegen` 後執行 `./codegen < test.c`，輸出寫到 **`codegen.S`** 檔案（不是 stdout）。
- 繳交檔案只有 `scanner.l`、`parser.y`、`makefile`，所以所有 C 程式碼都要放在這 3 個檔案裡。
- 每個函式輸出成 `.global name` / `name:` 的格式。
- RV64：用 `ld`/`sd` 做 8-byte 存取。
- **禁止靜態最佳化**：不能做 constant folding、constant propagation、dead code elimination。
- `HIGH` = 1、`LOW` = 0。
- 函式呼叫要遵守 RISC-V calling convention：參數放在 `a0`–`a7`，回傳值放在 `a0`，呼叫者要保存 caller-saved registers。

## 測資與配分

| 等級 | 測資 | 配分 | 需要的功能 | Spike 預期輸出 |
|---|---|---|---|---|
| E | Basic/0 | 50 | 函式結構、呼叫 `digitalWrite`/`delay`、`HIGH`/`LOW` | `(26,1)` `1000` `(26,0)` `1000` |
| D | ArithmeticExpression/0 | 5 | 區域變數、`+ - * /`、括號 | `(26,1)` `3000` `(26,0)` `3000` |
| D | ArithmeticExpression/1 | 5 | 同上 | `(27,1)` `4000` `(27,0)` `6000` |
| C | Pointer/0 | 5 | `&`、`*`、負數、指標賦值 | `(28,1)` `4000` `(28,0)` `4000` |
| C | Pointer/1 | 5 | 指標重新指向 | `(29,1)` `5000` `(29,0)` `2000` |
| B | Jump/0 | 5 | `for`、`while`、`if/else`、`!=`、`<`、1D 陣列、`*(arr+i)`、區塊內宣告 | `(26,1)` `3000` `(26,0)` `1000` |
| B | Jump/1 | 5 | `do-while`、巢狀 if、`int *f1 = fib + i - 1` | `(28,1)` `6000` `(28,0)` `4000` |
| A | Function/0 | 5 | 一般函式呼叫、遞迴（gcd）、`const int *` 參數、對參數取址 `&a` | `(28,1)` `6000` `(28,0)` `1000` |
| A | Function/1 | 5 | 陣列當參數、`const int` 區域變數、遞迴 | `(26,1)` `8000` `(26,0)` `3000` |
| Hidden | — | 10 | 與 A 類似 | — |

表中 `(26,1)` 代表 `Arduino digitalWrite(26, 1);`，`1000` 代表 `Arduino delay(1000);`。預期值取自測資裡的註解；Function/0 的 pin 是 `26 + modulo(6, 4)`，也就是 28。

## 架構決策

### 決策 1：建 AST 再走訪產生程式碼（不在 Yacc action 裡直接輸出）

規格的提示和講義示範的是在 action 裡直接 `fprintf`。建議改成先建 AST，原因如下：

- 迴圈、`break`/`continue`、`return` 需要 label，在 AST 上走訪時比較容易管理。
- 開始輸出函式之前就能算出整個 frame 的大小，prologue 可以一次配置好。
- 指標運算需要知道運算元的型別，例如 `fib + i - 1` 要乘上元素大小，AST 節點上可以記錄型別。
- Bonus 要切換 RV32，只要在走訪時換掉 `WORD`、`LOAD`、`STORE` 參數即可。
- 每個階段的職責清楚，除錯時能分別檢查 AST 和產生的組語。

代價是 `parser.y` 會比較長，預估 1200–1500 行。用註解分成 AST、symbol table、codegen 3 個區塊。

### 決策 2：Stack machine 式的運算式求值

- 每個運算式的結果放在 `t0`；二元運算的左側結果先 push 到 stack，算完右側之後再 pop 到 `t1`。
- 暫存值都放在 stack 上，呼叫函式前不需要另外保存 caller-saved registers。
- 這種做法產生的程式碼很長，但正確性容易驗證，也符合「不得最佳化」的規定。

### 決策 3：Stack frame 配置

```
高位址  ┌──────────────┐ ← 呼叫者的 sp
        │ ra           │ s0-8
        │ old s0       │ s0-16
        │ 參數 a0..a7  │ 存進自己的 slot，這樣 &a 才拿得到位址
        │ 區域變數     │ 每個宣告配一個獨立 slot（不重複使用）
        │ 陣列         │ 元素 0 放在最低位址，讓 arr+i 往高位址走
低位址  └──────────────┘ ← s0 - frame_size（16-byte 對齊）
        │ 運算暫存 push/pop │
```

- 每個 `int` 和指標都占一個 `WORD`（RV64 是 8 byte）。所以指標加減的縮放係數就是 `WORD`，陣列元素間距也是 `WORD`。
- 用 symbol table 記錄 `name → (scope, kind, type, offset)`。進入 `{}` 時 push 一層 scope，離開時 pop；shadowing 時取最內層的定義。

## 開發階段

每完成一個階段都要讓對應的測資通過才往下做。

| 階段 | 內容 | 狀態 |
|---|---|---|
| 3.0 | 從 HW2 複製 grammar；scanner 加上 `HIGH`、`LOW`；action 改成建 AST；`main` 開啟 `codegen.S` | ✅ |
| 3.1 | 函式 `.global` 框架、prologue/epilogue、函式呼叫 | ✅ Basic |
| 3.2 | symbol table、區域變數、`=`、`+ - * / %`、一元負號 | ✅ Arithmetic ×2 |
| 3.3 | `&`、`*`（讀取與寫入的 lvalue）、指標型別 | ✅ Pointer ×2 |
| 3.4 | 比較、`&&`/`||` 短路、`!`；`if`、`while`、`do-while`、`for`、`break`、`continue`、`switch`；1D 陣列、指標縮放 | ✅ Jump ×2 |
| 3.5 | 參數傳遞（a0–a7）、`return`、遞迴、陣列參數 | ✅ Function ×2 |
| 3.6 | 自建 6 組測資模擬 hidden（見下方） | ✅ 6/6 |
| 3.7 | 參數化 `WORD`/`LOAD`/`STORE`，`--rv32` 旗標 | ✅ 15 組測資在 RV32 下都能組譯 |
| — | AST dump（`-d`） | 未做，目前沒有需要 |

2026-11-23 完成：公開測資 9/9、自建測資 6/6 在 Spike 上通過；GNU gcc 0 warning（`-Wall -Wextra` 也是）；byacc 0 conflict。

### 自建測資（`tests/extra/`）

預期輸出由 `tests/native_expected.sh` 產生：用本機 gcc 編譯同一份 C 程式（`tests/native_harness.h` 提供 `digitalWrite`、`delay` 和 `main`），所以標準答案不是手算的。助教的 9 個測資也用同樣方法交叉驗證過，和依註解手寫的 `.expected` 完全一致。

| 測資 | 涵蓋內容 |
|---|---|
| ops | 所有算術、位元、比較、邏輯運算子；負數的 `/`、`%`、`>>` |
| control | `continue`/`break`、巢狀 if-else、`do-while` 搭配 `continue`、`switch` fall-through 與 `default`、`for(;;)` |
| calls | 6 個參數、函式呼叫當參數、遞迴（`fact(10)`）、指標參數 swap、回傳指標並對它賦值 |
| pointer_array | 指標 `++`/`--`、指標相減、`&a[i]`、陣列初始化、全域變數與全域陣列 |
| scope_incdec | block scope shadowing、前置／後置 `++`/`--` 的值、連續賦值 |
| short_circuit | `&&`/`||` 短路時，右邊有副作用的函式不能被呼叫 |

### 目前的限制

- 只支援整數與單層指標，`float`/`double` 字面值、字串字面值會回報錯誤
- 陣列只支援 1 維，長度必須是整數常數
- 函式最多 8 個參數（不支援經由 stack 傳遞的參數）
- `int` 在 RV64 上以 8 bytes 運算，溢位行為和 C 的 32-bit `int` 不同

## 測試流程

`hw3-codegen/tests/run.sh`，透過 `dev/run.sh make -C hw3-codegen test` 在容器內執行。以下是它的核心邏輯：

```sh
for t in testcases/*/*.c tests/extra/*.c; do
  ./codegen < "$t"                                   # 產生 codegen.S
  cp codegen.S build/ && cp spike-sample/main.c build/
  riscv64-unknown-elf-gcc -o build/prog build/main.c build/codegen.S
  spike pk build/prog | grep '^Arduino' > build/out.txt
  diff build/out.txt "${t%.c}.expected" && echo "PASS $t" || echo "FAIL $t"
done
```

每個測資都需要 `.expected` 檔，依上表內容寫成 4 行 `Arduino ...`。

## 風險

| 風險 | 對策 |
|---|---|
| Spike 和 pk 在 Apple Silicon 的 Docker 裡編不起來 | 改用 `riscv64-linux-gnu-gcc -static` 加 `qemu-riscv64`（見 [environment.md](environment.md)） |
| `int` 用 8 byte 和 C 語意不同（例如溢位） | 測資不涉及溢位；在 README 註明這個設計取捨 |
| 除法是負數時的行為 | RISC-V 的 `div` 向零截斷，和 C 相同（Pointer/0 有 `-a / 8`） |
| `parser.y` 太長、不好維護 | 嚴格分區、函式命名加前綴（`ast_`、`sym_`、`gen_`） |

預估工作量：4–6 天。
