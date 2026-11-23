# 開發環境

所有建置與測試都在 **Colima VM 裡的 Docker 容器** 中執行，macOS 本機不需要安裝 flex/yacc/RISC-V 工具鏈。

## 架構

```
macOS
└─ Colima VM（profile: compiler，aarch64，4 CPU / 6 GB / 30 GB）
   └─ 容器 nthu-compiler:latest（Ubuntu 24.04）
      ├─ gcc 13.3、flex 2.6.4、byacc 2.0（`yacc` 指向 byacc，與課程 server 相同）
      ├─ riscv64-unknown-elf-gcc   → xPack riscv-none-elf-gcc 14.2.0-3 的包裝，固定 -march=rv64gc -mabi=lp64d
      ├─ spike（riscv-isa-sim 982f078）
      ├─ pk（riscv-pk 9c61d29，RV64）
      └─ pk32（RV32 版，/opt/riscv32/riscv-none-elf/bin/pk；Spike 要給完整路徑）
```

repo 根目錄會掛載到容器的 `/work`，並以你的 uid/gid 執行，產生的檔案擁有者跟本機一樣。

## 常用指令

```sh
colima start compiler          # 開機（重開機後需要）
colima stop compiler           # 不用時關機
dev/run.sh --build             # 建置映像檔（Dockerfile 改動後）
dev/run.sh                     # 進入容器 shell，工作目錄對應目前所在的子目錄
dev/run.sh make -C hw2-parser test

cd hw1-scanner && ../dev/run.sh make test
```

`dev/run.sh` 一律使用 `--context colima-compiler`，不會改變本機 docker 的預設 context。

### 實作報告（PDF）

```sh
dev/run.sh dev/report/build.sh        # 重新產生 4 份報告（LuaLaTeX）
dev/run.sh dev/report/build.sh hw3    # 只產生路徑包含 hw3 的報告
```

報告的原始檔是各作業 `report/` 底下的 `*_Implementation_Report.tex`，共用樣式在 `dev/report/report.sty`。報告裡的程式碼片段是建置時用 `\snippet` 從原始碼擷取的（以程式碼內容定位，不寫死行號），改了程式之後重新建置即可同步。

## 首次建置時遇到的問題（已解決）

| 問題 | 原因 | 解法 |
|---|---|---|
| Ubuntu 的 `gcc-riscv64-unknown-elf` 無法連結 `main.c` | 套件不含 newlib（沒有 libc） | 改用 xPack 預建工具鏈（含 newlib，有 arm64 版，下載時驗證 sha256） |
| Spike 編譯失敗：找不到 `softfloat.h` | 新版 Spike 把 softfloat 拆成 git submodule | 一併取得 submodule；Spike 與 pk 都固定在特定 commit（Dockerfile 的 `SPIKE_COMMIT`、`PK_COMMIT`），本機和 CI 結果一致 |
| `spike pk` 找不到 pk | Spike 到 `<prefix>/riscv64-unknown-elf/bin/` 找 pk，但 xPack 的 target 名稱是 `riscv-none-elf` | 建立目錄 symlink |
| `yacc` 是 bison | Ubuntu 的 alternatives 預設指向 bison | `/opt/riscv/bin/yacc → byacc`，放在 PATH 最前面 |
| `dev/run.sh` 報 `unbound variable` | macOS 內建 bash 3.2 在 `set -u` 下展開空陣列會出錯 | 改用 `${arr[@]+"${arr[@]}"}` |

## 驗證紀錄（2026-11-23）

- [x] 助教的 `hw3-codegen/spike-sample` 在 Spike 上輸出 4 行正確的 Arduino log（新版 pk 不印 `bbl loader`）
- [x] HW1：GNU gcc 0 warning（`-Wall` 也是），8/8 測資通過
- [x] HW2：byacc 0 conflict，GNU gcc 0 warning，9/9 測資通過
- [x] HW3：RV64 15/15、RV32 15/15（`spike --isa=rv32imac` + pk32）
- [x] HW3 Bonus：5/5（P-extension 以 C 參考實作模擬）

## HW3 Bonus 額外環境

- Andes 的 RV32 + P-extension toolchain 包含在 Arduino 的 Corvette board package 裡（Windows）。
- xPack gcc 有 rv32 multilib，可以先用它檢查 RV32 組語（`riscv-none-elf-gcc -march=rv32imac -mabi=ilp32 -c`），但組譯不了 `ukadd8` 這類 P-extension 指令。
- 標準 Spike 已移除 P-extension 草案，無法模擬。

## CI

[.github/workflows/ci.yml](../.github/workflows/ci.yml) 在每次 push 時用同一份 Dockerfile 建置 `toolchain` stage（不含 LaTeX），再跑 HW1、HW2、HW3（RV64、RV32）與 Bonus 的全部測試。映像檔的 layer 用 GitHub Actions cache 保存，只有第一次需要從原始碼編譯 Spike。
