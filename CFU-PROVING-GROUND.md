# CFU-Proving-Ground on NixOS

この dotfiles は [CFU-Proving-Ground](https://github.com/archlab-sciencetokyo/CFU-Proving-Ground)
の **RTL シミュレーション・RISC-V プログラム生成・Vivado bitstream 生成**に必要な環境を用意する。
上流ソースは変更しない。上流の Makefile は研究室の `/tools/...` を絶対パスで参照しているため、
`cfu-make` コマンドでツールのパスを上書きする。

## 対応するツール

- Verilator 5、GCC/Make、Cairo/X11 (ディスプレイエミュレーター)
- RISC-V bare-metal GCC/binutils (**rv32im / ilp32** に合わせて Nix で用意)
- `bc`、`grep -P`、`hexdump`、`perl` など上流 Makefile が使うコマンド
- `vivado` / `vivado-fhs` (AMD Vivado 本体は別途インストール)

RV32IM/ILP32 用の cross GCC と newlib は標準の Nixpkgs クロス設定と ABI が違う場合があるため、
専用のクロス設定を使う。**最初の NixOS rebuild で GCC / newlib の大きなソースビルドが発生する可能性がある。**

## 使用方法

```sh
sudo nixos-rebuild switch --flake .#nixos

git clone https://github.com/archlab-sciencetokyo/CFU-Proving-Ground.git
cd CFU-Proving-Ground

cfu-make prog             # RISC-V プログラムとメモリ初期化ファイルを生成
cfu-make build            # Verilator と Cairo/X11 の表示エミュレーターをビルド
cfu-make drun             # X11 (Hyprland では XWayland) で表示。終了は Ctrl-C

cfu-make init             # デフォルトボード: Arty A7
cfu-make bit              # Vivado で bitstream を生成
```

`cfu-make` は GNU make にそのまま引数を渡す。例:

```sh
cfu-make -C /path/to/CFU-Proving-Ground TARGET=nexys_a7 init
cfu-make TARGET=nexys_a7 bit
cfu-make TARGET=cmod_a7 init
```

**ボードを変更した場合は** `cfu-make TARGET=<board> init` を再実行し、対応する
XDC/Tcl をコピーすること。FPGA のハードウェア実行には対象ボード、表示器の適切な配線、
Vivado に該当 FPGA のデバイスサポートが必要。

## Vivado の設定

既にインストールされている Vivado 2024.1 を使用する場合は、Home Manager の
`XILINX_VIVADO` を `/home/hotaru/xilinx/Vivado/2024.1` に設定している。
ログインシェルを開き直せば手動 `export` は不要。

```sh
printf '%s\n' "$XILINX_VIVADO"
vivado -version  # Vivado は '--version' ではなく '-version'
```

**上流で動作確認されたのは Vivado 2024.2**。2024.1 はユーザーの現行環境に合わせており、
`cfu-make bit` での互換性は別途確認する必要がある。2026.1 等に変更した場合は
Home Manager の `XILINX_VIVADO` も更新する。

## HLS と FPGA 書き込み (別途準備が必要)

上流の `cfu-make vpp` / `cfu-make USE_HLS=1 bit` は **Vitis HLS の `v++`** と
生成済み CFU の Verilog を前提にする。Vitis はこの設定では自動導入しない。
必要なときは `cfu-make VPP=/path/to/v++ vpp` を使用する。

`cfu-make conf` は上流の `scripts/prog_dev.tcl` に書かれた IP/ポートの
Vivado Hardware Server に接続する。初期値は実際の IP アドレスではないため、
対象 FPGA と接続先に合わせた編集が必要。

## 確認と既知の制限

```sh
cfu-make --version        # GNU make のバージョン
cfu-make prog
cfu-make build
```

- `cfu-make` のツールパス指定は自動化しているが、Vivado のライセンス・デバイス・実機は提供しない。
- RTL シミュレーションの GUI 表示には X11/XWayland セッションが必要。
- CI ではラッパーの引数と設定の評価を検証できるが、Vivado/HLS/JTAG の実機動作は検証できない。
- 上流の Makefile には `clean` 等の破壊的なターゲットもあるので、使用前に内容を確認する。
