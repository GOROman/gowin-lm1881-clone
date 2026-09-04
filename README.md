# gowin-lm1881-clone

GOWIN FPGA (Tang Nano 9K / GW1NR-9C, HDMI 付き) で **LM1881 相当のビデオ同期分離 (Video Sync Separator)** を作るプロジェクト。

コンポジットビデオ (NTSC / PAL) から以下を取り出します。LM1881 と同じピン機能を Verilog で再現しています。

| 出力 | LM1881 ピン | 内容 |
|---|---|---|
| `csync_n`    | pin 1 COMPOSITE SYNC OUT | 複合同期 (負論理、入力をクリーンアップしたもの) |
| `vsync_n`    | pin 3 VERTICAL SYNC OUT  | 垂直同期 (負論理、垂直同期期間中 L) |
| `burst_n`    | pin 5 BURST/BACK PORCH   | バーストゲート (負論理、H同期後縁から 0.6us 遅れて 2.5us) |
| `odd_even`   | pin 7 ODD/EVEN           | フィールド判別 (奇数フィールド H) |
| `hsync_n`    | (LM1881 には無し)        | 水平同期 (負論理、等化パルス除去済み・固定幅) |
| `locked`     | (LM1881 には無し)        | 同期検出中フラグ |

追加で、HDMI 出力にステータス (同期波形のオシロ風表示・フィールド判定・ライン数) を表示します。

## ハードウェア

- ボード: **Sipeed Tang Nano 9K** (GW1NR-LV9QN88PC6/I5, 27 MHz 水晶, HDMI コネクタ)
- ビデオ入力フロントエンド: コンポジット信号を比較器で 2 値化して FPGA に入れる (後述)

## 作業 STEP

各 STEP ごとに 1 コミットしています。`git log` と対応します。

- [x] **STEP 0**: リポジトリ作成 (public)、README に計画を書く
- [ ] **STEP 1**: コア RTL `rtl/sync_separator.v` と NTSC 模擬テストベンチ `sim/tb_sync_separator.v` (iverilog で検証)
- [ ] **STEP 2**: Tang Nano 9K 用トップ `rtl/top_tang_nano_9k.v`、ピン制約 `constr/tang_nano_9k.cst`、スライスレベル用 PWM DAC
- [ ] **STEP 3**: HDMI ステータス表示 (640x480@60, TMDS エンコーダ, 同期波形表示)
- [ ] **STEP 4**: GOWIN EDA (`gw_sh`) で合成 → ビットストリーム生成 → `openFPGALoader` で書き込み、Makefile 整備

## ライセンス

MIT
