# 開發總覽

更新日期：2026-11-23

## 各作業狀態

| 作業 | 狀態 | 檔案 | 設計筆記 |
|---|---|---|---|
| HW1 Scanner | ✅ 8/8 測資，GNU gcc 0 warning | `scanner.l`、`makefile`、`tests/` | [hw1-plan.md](hw1-plan.md) |
| HW2 Parser | ✅ 9/9 測資，byacc 0 conflict，0 warning | `scanner.l`、`parser.y`、`makefile`、`tests/` | [hw2-plan.md](hw2-plan.md) |
| HW3 Codegen | ✅ 公開 9/9、自建 6/6，RV64 與 RV32 都在 Spike 上通過 | `scanner.l`、`parser.y`、`makefile`、`tests/` | [hw3-plan.md](hw3-plan.md) |
| HW3 Bonus | ✅ 5/5 測資（模擬執行）通過；上板驗證需要開發板 | 程式在 `hw3-codegen/`，測資在 `bonus/` | [hw3-bonus-plan.md](hw3-bonus-plan.md) |

> 所有作業都在 Docker 容器（GNU gcc + byacc + Spike）裡驗證，CI 也跑同一份環境，見 [environment.md](environment.md)。

## 依賴關係與開發順序

```
環境建置 ─► HW1 scanner ─► HW2 parser ─► HW3 codegen ─► HW3 Bonus
                          (grammar)     (AST + codegen)  (RV32 + intrinsics)
```

- HW2 的 scanner 由 HW1 改寫而來，HW3 的 grammar 和 HW2 相同（規格寫明「Token/Syntax requirement is the same as HW1/2」）。前一階段的問題會一路傳下去，所以依序完成、每一階段都要通過測試才往下做。
- 規格要求 HW3 和 Bonus 用**同一份** `scanner.l` / `parser.y`，以 flag 切換成 32-bit。Bonus 的程式碼放在 `hw3-codegen/` 裡，`bonus/` 目錄只放規格、測資和開發板範例。

| 階段 | 內容 | 驗收標準 |
|---|---|---|
| 0 | 環境建置（[environment.md](environment.md)） | Docker 裡能跑 `flex`、`byacc`、`riscv64-unknown-elf-gcc`、`spike pk` |
| 1 | HW1 scanner | 測資全部通過，`gcc -Wall` 沒有 warning |
| 2 | HW2 parser | `yacc -v` 沒有 conflict，測資全部通過 |
| 3 | HW3 codegen | 公開測資與自建測資在 Spike 上的輸出符合預期 |
| 4 | HW3 Bonus | RV32 組語能組譯，intrinsic 結果與 C 參考實作相同 |

## 測試策略（共通）

助教的 `golden_scanner` / `golden_parser` 在課程 server 上，已經無法使用。所以：

1. 每份作業都有 `tests/` 目錄，放 `*.c` 輸入和對應的 `*.expected`。
2. 預期輸出依規格投影片的範例和規則撰寫，有疑義的地方在設計筆記裡註明。
3. 每份作業都有 `make test`，逐一跑測資並 `diff`。
4. HW3 的預期輸出用本機 gcc 執行同一份 C 程式產生（differential testing），再和測資註解交叉比對。

## 待確認事項

1. **Bonus 開發板**：最終驗證需要 Andes Corvette-F1/T1 開發板和 Windows 上的 Arduino IDE。沒有開發板時，驗證範圍是「組譯通過，並用 C 參考實作比對語意」。
2. ~~**公開 repo 的版權**~~：保留課程教材，在 README 的 Acknowledgements 和 LICENSE 註明教材版權屬於原作者、不在 MIT 授權範圍內。
3. ~~**參考資料**~~：程式碼裡不放出處註記；在根目錄 README 的 Acknowledgements 說明曾參考同課程其他人的 GitHub repo 作為實作靈感。
