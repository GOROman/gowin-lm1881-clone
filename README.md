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
- [x] **STEP 1**: コア RTL `rtl/sync_separator.v` と NTSC 模擬テストベンチ `sim/tb_sync_separator.v` (iverilog で検証)
- [x] **STEP 2**: Tang Nano 9K 用トップ `rtl/top_tang_nano_9k.v`、ピン制約 `constr/tang_nano_9k.cst`、スライスレベル用 PWM DAC (gw_sh で合成・配置配線 OK)
- [x] **STEP 3**: HDMI ステータス表示 (640x480@60, TMDS エンコーダ, 同期波形表示)
- [x] **STEP 4**: GOWIN EDA (`gw_sh`) で合成 → ビットストリーム生成 → `openFPGALoader` で書き込み、Makefile / CI 整備

## STEP 1: コア RTL の設計

`rtl/sync_separator.v` はすべて **パルス幅と間隔の時間計測** で動く純デジタル回路です (ADC 不要、比較器で 2 値化した同期信号だけを使う)。

```
video_in ─▶ 2段FF同期化 ─▶ グリッチフィルタ(0.3us) ─▶ csync_n
                                   │
                                   ├─▶ L幅計測 ──▶ 分類: EQ(<3.5us) / H(<7us) / BROAD(<40us)
                                   │                      │
                                   │                      ├─▶ 最初のBROADで vsync_n=L、非BROADで H
                                   │                      ├─▶ そのとき先頭位相がライン先頭なら odd_even=1
                                   │                      └─▶ H/EQ 後縁 +0.6us から 2.5us burst_n=L
                                   │
                                   └─▶ 先頭エッジ: 前回 HSYNC から 3/4 ライン以上なら hsync_n パルス
                                       (半ライン間隔の等化/切り込みパルスを除去)
```

時定数はすべて `CLK_HZ` パラメータから計算されるので、27 MHz でも 25.2 MHz でも動きます。NTSC / PAL の判別は不要 (パルス幅は共通)。

### シミュレーション

```sh
make sim      # iverilog でNTSC 525本×3フレーム + ノイズ + 信号喪失を流して PASS/FAIL 判定
```

チェック内容: VSYNC 幅、フィールドごとの HSYNC 数 (NTSC 262/263、PAL 312/313 交互)、ODD/EVEN の交番、BURST の遅延/幅、NTSC→PAL 切替への追従、信号喪失で `locked` が落ちること。
波形は `sim/out/tb_sync_separator.vcd` (GTKWave 等で確認)。

## STEP 2: Tang Nano 9K トップと入力フロントエンド

### クロック
27 MHz 水晶 → rPLL (×14/3) = 126 MHz → CLKDIV/5 = **25.2 MHz**。これを同期分離と (STEP 3 の) HDMI ピクセルクロックで共用します。

### ピン配置 (`constr/tang_nano_9k.cst`)

| 信号 | ピン | 備考 |
|---|---|---|
| `video_in`  | 25 | 比較器出力 (同期チップで L) |
| `slice_pwm` | 26 | PWM 出力 → RC 平滑 → 比較器の基準電圧 |
| `csync_n`   | 27 | 複合同期 |
| `hsync_n`   | 28 | 水平同期 |
| `vsync_n`   | 29 | 垂直同期 |
| `burst_n`   | 30 | バーストゲート |
| `odd_even`  | 31 | フィールド |
| `locked`    | 32 | ロック |
| LED0..5 | 10,11,13,14,15,16 | locked / odd_even / フィールド点滅 / PLL lock / 入力あり / AGC hold |
| S1 (pin 3) | | 押している間 AGC 停止 |
| S2 (pin 4) | | リセット |

ピン 25〜32 は 3.3V バンクです。(LED は 1.8V バンクなので `IO_TYPE` を付けない)

### 入力フロントエンド (外付け回路)

FPGA には ADC が無いので、比較器 1 個で同期チップだけを 2 値化します。

```
                          3.3V
                           │
コンポジット ──┤├── 100nF ──┼──┬──────── (+) ┐
   (75Ω終端)              ▽ 1N4148     │  比較器  ├──▶ video_in (pin 25)
                     (同期チップクランプ) │ LMV331 等│
 slice_pwm (pin 26) ── 10k ──┬────────── (-) ┘
                            100nF
                             ┴
```

* 同期チップ (最も低い電位) がダイオードでクランプされ、`slice_pwm` を平滑した基準電圧より下の区間だけ出力が L になる。
* `rtl/slice_agc.v` が H 同期パルスの幅を監視し、4.0〜5.5 us に収まるよう基準電圧を自動追従、非ロック時は掃引して同期を探す。
* 比較器の代わりに 74HC14 等のシュミットトリガでも「一応」動く (レベル固定)。

### ビルド

```sh
make build        # gowin/gw_sh.sh 経由で GOWIN EDA (合成〜ビットストリーム) → impl/pnr/lm1881_clone.fs
make flash-sram   # openFPGALoader で SRAM に書き込み
make flash        # 内蔵 Flash に書き込み
```

`gowin/gw_sh.sh` は macOS 版 GOWIN EDA (`/Applications/GowinIDE.app`) の `gw_sh` に DYLD パスを通すラッパ。別の場所なら `GOWIN_HOME` で指定。

## STEP 3: HDMI ステータス表示

HDMI (DVI 信号) に 640x480@60 で状態を表示します。ADC もフレームバッファも無いので映像そのものは出ませんが、
「同期がちゃんと取れているか」をモニタ 1 台で確認できます。

![HDMI 画面 (シミュレーションで描画)](docs/hdmi_screen_sim.png)

* 上段: LOCK / PLL / FIELD(ODD/EVEN) / 入力あり、フィールドのライン数、H 周期 [us]、同期パルス幅 [us]、スライスレベル duty
* **H VIEW**: HSYNC トリガで 1 ライン分 (3clk/px = 76us) の CS/HS/VS/BG 波形
* **V VIEW**: VSYNC トリガで 6.4 ライン分 (16clk/px = 406us)。切り込みパルス→等化パルス→通常ラインの遷移と VSYNC 出力が見える

構成 (`rtl/hdmi/`):

| ファイル | 内容 |
|---|---|
| `hdmi_tx.v` | 640x480 タイミング生成、TMDS 3ch + クロックを `OSER10` (10:1) → `ELVDS_OBUF` で出力 |
| `tmds_encoder.v` | DVI 1.0 の 8b/10b エンコーダ |
| `status_display.v` | 波形キャプチャ (BSRAM 2 本)、テキスト描画、数値→BCD |
| `font5x7.v` / `screen_text.v` | `tools/gen_font.py` / `tools/gen_screen.py` が生成する 5x7 フォントと固定文言 |

画面はシミュレーションでも描画できます (`make sim-display` → `sim/out/frame.png`)。GOWIN プリミティブは `sim/gowin_stubs.v` で代用。

リソース: LUT 1867 / 8640 (22%)、FF 546、BSRAM 2/26。タイミング: clk_pix 25.2 MHz に対し Fmax 26.4 MHz。

## STEP 4: ビルドと書き込み

```sh
make sim          # RTL シミュレーション (PASS が出ること)
make sim-display  # HDMI 画面を 1 フレーム描画 → sim/out/frame.png
make build        # GOWIN EDA で合成〜ビットストリーム (impl/pnr/lm1881_clone.fs)
make flash-sram   # Tang Nano 9K の SRAM に書き込み (試用向け)
make flash        # 内蔵 Flash に書き込み (電源投入で起動)
```

* `openFPGALoader -b tangnano9k` を使用。デバイスが見えないときは USB ケーブル (データ線付き) と FTDI ドライバを確認。
* GitHub Actions (`.github/workflows/sim.yml`) で push ごとに `make sim` / `make sim-display` を実行し、画面 PNG を artifact に残します。

### 未検証・注意

* 合成時に `font5x7 ... is swept in optimizing` と警告が出ますが階層フラット化によるもので、テキスト描画を無効化した比較ビルド (LUT 729) との差分からフォント/テキスト論理は実装に残っていることを確認済み。
* **実機未確認** です (手元にボードが無い状態で作成)。シミュレーション (NTSC 同期波形 + ノイズ) と GOWIN EDA の配置配線・タイミング (clk_pix Fmax 26.4 MHz > 25.2 MHz) までは通っています。
* 出力は 3.3V。LM1881 のような 5V 系に繋ぐ場合はレベルの確認を。
* HDMI 出力の LVDS バッファは `ELVDS_OBUF` (Sipeed サンプルと同じ)。

## ビルド済みビットストリーム

GOWIN EDA を入れなくても試せるよう、`bitstream/lm1881_clone.fs` をリポジトリに同梱しています (タグ [v0.1.0](https://github.com/GOROman/gowin-lm1881-clone/releases/tag/v0.1.0) 時点のビルド)。

```sh
openFPGALoader -b tangnano9k -f bitstream/lm1881_clone.fs
```

## 使い方

### 必要なもの

| 品名 | 数量 | 備考 |
|---|---|---|
| Sipeed Tang Nano 9K | 1 | USB-C ケーブル (データ線付き) も |
| HDMI モニタ + ケーブル | 1 | 状態表示用 (無くても動く) |
| 比較器 IC | 1 | LMV331 / LM393 / LM339 / TLV3201 など 3.3V 単電源で動くもの |
| 1N4148 (小信号ダイオード) | 1 | 同期チップクランプ |
| コンデンサ 0.1uF | 2 | 結合用 / PWM 平滑用 |
| 抵抗 75Ω, 10kΩ×2, 22kΩ, 220kΩ | | 終端 / RC / クランプ電圧分圧 / 放電 |
| RCA ジャック or ケーブル | 1 | コンポジット入力 |
| ブレッドボード、ジャンパ | | |

### コンポジット信号の入れ方 (フロントエンド回路)

FPGA には ADC が無いので、**同期チップ (信号の一番低いところ) だけを比較器で 2 値化** して入れます。
コンポジット信号 (1Vp-p) は 同期チップ 0V / ブランキング 0.3V / 白 1.0V なので、
「同期チップとブランキングの間 (約 0.15V)」にしきい値を置けば同期だけが切り出せます。

```
                                    3.3V
                                     │
                                    22k
                                     │
                          Vclamp ≈1.0V ├──── 1N4148 ───┐  (アノード:Vclamp, カソード:ノード)
                                    10k                │
                                     │                 │
                                    GND                │
                                                       │
 RCA ──┬──── 0.1uF ────────────────────────────────────┼───┬───────▶ 比較器 (+)
      75Ω                                              │  220k
       │                                               │   │
      GND                                             GND GND

 Tang Nano 9K pin 26 (slice_pwm) ──── 10k ────┬───────▶ 比較器 (−)
                                            0.1uF
                                              │
                                             GND

 比較器 OUT ─────────────────────────────────────────▶ Tang Nano 9K pin 25 (video_in)
   (LM393/LM339 などオープンコレクタ出力の場合は 10k で 3.3V にプルアップ)
 比較器 VCC = 3.3V (Tang Nano 9K の 3V3 ピンから), GND 共通
```

動作:

1. 0.1uF で AC 結合し、ダイオードで **同期チップを Vclamp − 0.6V ≈ 0.4V に固定** (クランプ)。220k はクランプを維持するための放電用。
2. FPGA の `slice_pwm` (8bit PWM, 約 98kHz) を 10k/0.1uF で平滑して比較器のしきい値にする。0〜3.3V を 256 段階で出せる。
3. 比較器は「ビデオ > しきい値」で H、同期チップで L を出す → `video_in`。
4. FPGA 側の AGC (`rtl/slice_agc.v`) が水平同期の幅を 4.0〜5.5us に保つようにしきい値を自動調整。
   ロックしていない間は 1ms ごとに 1 段階ずつ掃引して同期を探す (最長 256ms で一周)。
   S1 を押している間は調整を止めて固定できる。

定数はクリティカルではありません。Vclamp は 0.8〜1.5V、放電抵抗は 100k〜1M の範囲なら OK。
比較器はヒステリシス無しでも FPGA 側の 0.3us グリッチフィルタで十分動きます。

#### 手抜き版 (比較器なし)

FPGA 入力ピンのしきい値 (LVCMOS33 で約 1.5V 前後) をそのまま比較器代わりに使う方法。
Vclamp 用の分圧を外して、**平滑した `slice_pwm` をクランプ電圧にする** と、AGC が「入力ピンのしきい値が同期チップの中に来る」ように自動で追い込みます。

```
 pin 26 (slice_pwm) ── 10k ──┬── 0.1uF ── GND
                             └── 1N4148 (アノード) ─┬─ (カソード) ── 220k ── GND
 RCA ── 75Ω/GND ── 0.1uF ───────────────────────────┴──────────────▶ pin 25 (video_in)
```

部品 5 点で済みますが、ノイズ耐性は比較器版に劣ります。まず動かしてみるには十分です。

#### 信号源について

* NTSC / PAL どちらも対応 (同期パルス幅は共通、ライン数だけ変わる: 262/263 または 312/313)。
* ゲーム機、ビデオデッキ、カメラ、Raspberry Pi のコンポジット出力など何でも可。
* S 端子の Y 信号、RGB(SCART) の CSYNC 信号もそのまま入る。
* テスト用に本物の LM1881 の CSYNC 出力 (pin 1) を `video_in` に直結しても動く (すでに 2 値なので比較器不要、5V 出力なら分圧して 3.3V に)。

### 起動手順

1. `make build` → `make flash` でビットストリームを Flash に書き込む (ボードを USB 接続して実行)。
2. 上のフロントエンド回路を組み、HDMI モニタを接続。
3. 電源投入で LED3 (PLL ロック) 点灯。HDMI モニタに `LM1881 CLONE` の画面が出る。
4. コンポジット信号を入れると LED4 (入力あり) 点灯。数百 ms 以内に AGC がしきい値を見つけ、LED0 (LOCK) が点灯し LED2 がフィールドごとに点滅する。
5. HDMI 画面で `LINES/FIELD` が 262/263 (NTSC) か 312/313 (PAL) で交互に変わり、`H:63.5us` `SYNC:4.7us` 前後になっていれば正常。
6. ヘッダピン 27〜32 から LM1881 相当の出力を取り出す (3.3V CMOS レベル)。

| ピン | 出力 | LM1881 対応 |
|---|---|---|
| 27 | `csync_n` 複合同期 (負論理) | pin 1 |
| 28 | `hsync_n` 水平同期 (負論理, 4.7us 固定幅) | — |
| 29 | `vsync_n` 垂直同期 (負論理) | pin 3 |
| 30 | `burst_n` バーストゲート (負論理) | pin 5 |
| 31 | `odd_even` 奇数フィールドで H | pin 7 |
| 32 | `locked` 同期検出中 H | — |

### HDMI 画面の見方

* **LOCK:[*]** 垂直同期を 50ms 以内に検出している / **PLL:[*]** クロック正常 / **FIELD:ODD/EVEN** 現在のフィールド / **IN:[*]** 何らかのパルスあり
* **LINES/FIELD** 直前フィールドのライン数、**H** 水平周期、**SYNC** 同期パルス幅、**SLICE DUTY** 現在のしきい値 (0〜255)
* **H VIEW** 1 ライン分の CS/HS/VS/BG 波形 (HSYNC トリガ)。CS の L 幅が 4.7us 相当 (約 40px) なら良好
* **V VIEW** 垂直同期付近 6.4 ライン分 (VSYNC トリガ)。幅広の切り込みパルス → 等化パルス → 通常ライン、VS が L→H に戻る様子が見える

### トラブルシュート

| 症状 | 確認すること |
|---|---|
| LED4 (入力あり) が点かない | 比較器の電源・出力プルアップ、75Ω 終端、GND 共通。`video_in` をテスタで見て H/L が動くか |
| 入力ありなのに LOCK しない | H VIEW で CS 波形を見る。パルスが太すぎ/細すぎなら Vclamp を 0.8〜1.5V の範囲で振る。S1 を押して DUTY を固定し様子を見る |
| SYNC が 2.3us や 30us 付近 | 等化/切り込みパルスに合ってしまっている → しきい値が低すぎ。AGC が動いていれば数百 ms で収束するはず |
| LINES が 262/263 で安定しない | ノイズ。比較器を TLV3201 などヒステリシス内蔵品にするか、`video_in` に 100pF を足す |
| HDMI に何も出ない | LED3 (PLL) 点灯を確認。モニタによっては DVI 信号 (音声なし) を受けないものがある |

## ライセンス

MIT
