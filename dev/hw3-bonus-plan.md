# HW3 Bonus 實作規劃：Andes P-extension Intrinsics

規格：[hw3-codegen/bonus/spec/HW3_Bonus_Spec.pdf](../hw3-codegen/bonus/spec/HW3_Bonus_Spec.pdf)
開發板環境：[Arduino_Env_Guide_Corvette-F1_T1.pdf](../hw3-codegen/bonus/spec/Arduino_Env_Guide_Corvette-F1_T1.pdf)
範例：[HW3_Bonus.ino](../hw3-codegen/bonus/arduino-sample/HW3_Bonus.ino)、[codegen.S](../hw3-codegen/bonus/arduino-sample/codegen.S)（手寫的 `ukadd8` 範例）、[testcases/0.c](../hw3-codegen/bonus/testcases/0.c)

前置條件：[HW3](hw3-plan.md) 的 9 個公開測資全部通過（規格的參加資格）。

## 規格重點

- 和 HW3 用**同一份** `scanner.l` / `parser.y`，以自訂 flag 切換到 RV32；預設仍然是 RV64。
- RV32 用 `lw`/`sw` 做 4-byte 存取。
- 要支援 4 個 SIMD 8-bit intrinsic：

| Intrinsic | 指令 | 語意（對 4 個 byte 分別運算） |
|---|---|---|
| `__rv__ukadd8(a, b)` | `ukadd8 rd, rs1, rs2` | 無號飽和加法：`min(a[i] + b[i], 255)` |
| `__rv__uksub8(a, b)` | `uksub8 rd, rs1, rs2` | 無號飽和減法：`max(a[i] - b[i], 0)` |
| `__rv__cmpeq8(a, b)` | `cmpeq8 rd, rs1, rs2` | `a[i] == b[i]` 時為 `0xFF`，否則為 `0x00` |
| `__rv__ucmplt8(a, b)` | `ucmplt8 rd, rs1, rs2` | 無號 `a[i] < b[i]` 時為 `0xFF`，否則為 `0x00` |

> 語意整理自 riscv-p-spec，實作前要再對照原始規格確認一次。

- 測資格式（以 `testcases/0.c` 為例）：函式名稱是 `ext_dsp_codegen`，有 2 個 `uint32_t` 參數，回傳 `uint32_t`；沒有 `codegen()` 也沒有 `digitalWrite`。
- 評分：4 個 hidden testcase，每個 1 分，佔學期總成績 4%。

## 需要新增的功能

| # | 項目 | 做法 |
|---|---|---|
| B1 | Target flag | `./codegen --rv32 < t.c`。也可以用環境變數 `CODEGEN_TARGET=rv32`，這樣不需要改 TA 的執行指令。在 `main()` 解析參數後，設定全域的 `WORD=4`、`LOAD="lw"`、`STORE="sw"` |
| B2 | `uint32_t` 型別 | scanner 新增 `UINT32_TYPE` token，parser 的 `type_spec` 加一條規則。AST 型別記錄 unsigned 屬性，必要時比較用 `sltu`、除法用 `divu` |
| B3 | Intrinsic 呼叫 | grammar 不用改，它們本來就是一般的函式呼叫。codegen 處理 call 節點時查表，名稱符合 `__rv__*` 就不輸出 `jal`，改成：先求值參數 0 並 push，再求值參數 1 到 `t1`，pop 參數 0 到 `t0`，然後輸出 `<op> t0, t0, t1` |
| B4 | RV32 frame | `ra`、`s0` 各占 4 byte，frame 一樣 16-byte 對齊（ILP32 ABI） |
| B5 | 非 `codegen` 的入口函式 | HW3 原本就是每個函式都輸出 `.global`，應該不用改。確認一下即可 |

## 實作狀態（2026-11-23）

| # | 項目 | 狀態 |
|---|---|---|
| B1 | `--rv32` 旗標（也支援 `CODEGEN_TARGET=rv32`） | ✅ HW3 的 15 個測資在 RV32 Spike 上全部通過 |
| B2 | `uint32_t` 型別與無號運算：比較用 `sltu`、除法用 `divu`/`remu`、右移用 `srl` | ✅ |
| B3 | 4 個 intrinsic，用查表方式輸出 `<op> t0, t1, t0`（rs1 = 第 1 個參數） | ✅ |
| B4 | RV32 frame（4-byte slot，16-byte 對齊） | ✅ |
| B5 | 非 `codegen` 的入口函式 | ✅ 不用改 |
| — | 上板驗證 | ⏳ 需要開發板 |

## 驗證方式（不需要開發板）

`dev/run.sh make -C hw3-codegen test-bonus`（腳本：`bonus/tests/run.sh`）會對每個 `bonus/testcases/*.c` 檢查以下 3 項：

1. **標準答案**：用本機 gcc 編譯測資，intrinsic 換成 C 參考實作（`bonus/tests/pext_ref.h`），以 12 組輸入執行。輸入包含規格範例和各 lane 的飽和、相等邊界值。
2. **實際結果**：`codegen --rv32 --pext-emulate` 產生組語，在 RV32 Spike 上執行，結果要和標準答案完全相同。模擬模式下，P-extension 指令換成呼叫同語意的 `__pext_<op>()`，傳入的運算元與正式輸出相同（`a0` = rs1、`a1` = rs2）。
3. **正式輸出**：`codegen --rv32` 產生的 `codegen.S` 就是要上板的版本。把 P-extension 指令暫時換成 `nop` 後，用 GNU as 組譯，確認其餘部分都是合法的 RV32 組語；也確認 intrinsic 數量和模擬模式一致，而且沒有殘留任何 `__rv__` 呼叫。

**變異測試**：刻意修改產生的組語，確認上面的測試抓得到錯誤。以下變異都會讓測試失敗：對調 intrinsic 的兩個運算元（1.c、2.c、3.c）；`sltu`→`slt`、`divu`→`div`、`srl`→`sra`（4.c）。第一版測資有兩個抓不到，2.c 是因為算式對稱，4.c 是因為差異被除法吃掉，已經改寫。

| 測資 | 內容 |
|---|---|
| 0.c | 助教提供 |
| 1.c | 區域變數串接 3 個 intrinsic |
| 2.c | 不具交換性的運算，檢查參數順序 |
| 3.c | 巢狀 intrinsic 呼叫 |
| 4.c | 混合無號比較、除法、右移；**CRLF 換行**（助教的 0.c 原本就是 CRLF） |

**沒有驗證到的部分**：C 參考實作的語意是依 riscv-p-spec 寫的，和 Andes 硬體是否完全一致，要上板才能確認。另外，Andes 組譯器能不能接受這些指令的寫法也還沒確認；寫法和助教範例 `ukadd8 a5, a4, a5` 相同，應該沒問題。

## 上板步驟（有開發板時）

1. 在容器內執行 `make -C hw3-codegen test-bonus`，要上板的檔案是 `hw3-codegen/build/bonus/<n>/codegen.S`。也可以直接執行 `./codegen --rv32 < testcase.c`。
2. 依 [Arduino_Env_Guide](../hw3-codegen/bonus/spec/Arduino_Env_Guide_Corvette-F1_T1.pdf) 安裝 Corvette board package，並在 `platform.txt` 加上 `-mext-dsp`。
3. 把 `HW3_Bonus.ino` 和產生的 `codegen.S` 放在同一個 sketch 資料夾，然後上傳。
4. 開啟 Serial Monitor，設定 No Line Ending、9600 baud，輸入 `65280, 65283`、`100, 200` 等數值，應該會看到 `The results are equal.`。
