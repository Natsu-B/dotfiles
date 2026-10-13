# Vivado on NixOS

Vivado は AMD から別途入手する。dotfiles は Vivado 本体やライセンスを配布せず、
Home Manager で `vivado` と `vivado-fhs` を提供する。
`vivado-fhs` は AMD のインストーラーおよび実行ファイル向けの FHS 環境。
NixOS は AMD の公式サポート対象 OS ではないため、全機能・全バージョンの動作を保証しない。

## インストール

1. この設定を `sudo nixos-rebuild test --flake .#nixos` で適用する。
   問題がなければ `sudo nixos-rebuild switch --flake .#nixos` を実行する。
2. [AMD のダウンロードページ](https://www.amd.com/en/support/adaptive-socs-and-fpgas/installer-info-general.html)
   から Linux 用 Vivado インストーラーを取得する。AMD アカウントとライセンスへの同意が必要。
   NixOS ではオフラインインストーラー（展開後に `xsetup` を含むもの）を推奨する。
3. インストーラーを FHS 環境内で起動する。**Web インストーラー (.bin) は展開不要**。
   以下は 2026.1 Linux 版を `~/Downloads` に保存した例:

   ```sh
   cd ~/Downloads
   chmod u+x FPGAs_AdaptiveSoCs_Unified_SDI_2026.1_0616_1700_Lin64.bin
   vivado-fhs -c 'exec "$1"' installer \
     "$PWD/FPGAs_AdaptiveSoCs_Unified_SDI_2026.1_0616_1700_Lin64.bin"
   ```

   AMD アカウントでログインし、通常は `Download and Install Now` を選択する。
   使用する FPGA に対応する device family と Vivado を選ぶ。Web インストーラーは
   選択したデータを追加でダウンロードする。

   オフライン版 (SFD / Full Image) を展開した場合は、代わりに展開先の
   `xsetup` を FHS 内で起動する:

   ```sh
   vivado-fhs -c 'exec "$1"' installer "$PWD/xsetup"
   ```

   インストール先は空白を含まない場所にする。ホームディレクトリの `~/Xilinx` などは
   root 権限なしで管理できる。インストール先の書き込み権限を事前に確認する。
   `sudo` を FHS 環境内から実行しない。

## 起動

インストール先が `/opt/Xilinx` の場合、2025.1 以降の例は
`/opt/Xilinx/2025.2/Vivado`、古い形式は `/opt/Xilinx/Vivado/2024.2`。
次のディレクトリを自動検索する:
`/opt/Xilinx`、`/opt/AMD`、`/opt/amd`、`~/Xilinx`、`~/AMD`、`~/amd`。

```sh
vivado -version
vivado                         # GUI
vivado -mode batch -source build.tcl
```

見つからない場合や複数バージョンがある場合は、対象の Vivado ディレクトリを指定する。
AMD の `settings64.sh` はラッパーが FHS 内で読み込むため、シェル全体に PATH や
`LD_LIBRARY_PATH` を永続設定する必要はない。

```sh
export XILINX_VIVADO="$HOME/Xilinx/2025.2/Vivado"
vivado -version
```

別のインストール先だけを検索する場合は `VIVADO_INSTALL_ROOT=/path/to/prefix vivado`。
複数バージョンを黙って切り替えず、明示指定を要求する。

## USB JTAG

`nixos/vivado.nix` は Digilent (0403:6010)、Xilinx Platform Cable USB II
(03fd:0008 / 03fd:0013) の USB デバイスへのアクセスを `plugdev` に付与する。
すでに `hotaru` ユーザーは `plugdev` に属する。全 USB デバイスを 0666 にしない。

```sh
lsusb
ls -l /dev/bus/usb/*/*
```

ケーブルによっては AMD 付属のドライバー・ファームウェアの追加設定が必要。
対象ボードで Vivado Hardware Manager の検出と書き込みを実機確認すること。

## 確認と制限

```sh
bash -n scripts/vivado.sh
python3 -m unittest tests/test_vivado.py -v
nix flake check --no-build
```

Vivado の実行ファイルとインストーラーは CI に含まれない。CI で検証するのは設定の評価と
ラッパーの挙動まで。実機の GUI、合成、シミュレーション、JTAG、ライセンス認証は別途確認する。
