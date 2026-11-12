# Ubuntu 用 xremap 設定

Natsu-B/dotfiles の `home/desktop/generate_xremap.py` を元に、
`変換 (HENKAN)` + キーを `Super` ショートカットにする Hyprland 向け処理を除去しました。
追加で無変換+M（英数）と変換+,（かな）を登録しています。

- `qwerty.yml`: JIS/QWERTY、無変換ナビゲーション、SandS、日本語切替キー
- `dvorak.yml`: 上記に加えて独自 Programmer Dvorak
- `generate_xremap.py`: プロファイル再生成用（Python 標準ライブラリのみ）

## 追加した IME 操作

| 物理キー | xremap が送信するキー | 意図する動作 |
|---|---|---|
| 無変換 + M | `MUHENKAN` | 英数（IME オフ） |
| 変換 + , | `HENKAN` | かな（IME オン） |

**xremap だけでは IME の ON/OFF を確定できません。** Ubuntu で Fcitx5 を使う場合は、
`fcitx5-configtool` のグローバルオプションで **入力メソッドを有効化** に `Henkan`、
**入力メソッドを無効化** に `Muhenkan` を登録してください。
これにより切替ではなく、それぞれ明示的な ON/OFF になります。
IBus など他の IME を使う場合は、同等のキー割り当てが別途必要です。

変換キー単独の扱いは xremap の仮想修飾キー設定に依存します。

## 導入

1. xremap を Ubuntu にインストールする（公式ビルドの利用方法を確認）。
2. Ubuntu のキーボード配列を **日本語 (JIS / jp)** にする。Dvorak を XKB 側でも設定しない。
3. `~/.config/xremap/profiles/` に YAML 2 個を配置する。
4. どちらか一つで起動する（環境に応じて sudo/権限設定が必要）。

```sh
mkdir -p ~/.config/xremap/profiles
cp qwerty.yml dvorak.yml ~/.config/xremap/profiles/
xremap ~/.config/xremap/profiles/dvorak.yml
# または
xremap ~/.config/xremap/profiles/qwerty.yml
```

権限は `/dev/input/event*` の読み取りと `/dev/uinput` への書き込みが必要です。
一部の xremap ビルドでは Wayland/X11 用の機能やオプションに差があります。

**注意:** 元の dotfiles では xremap に独自パッチを適用しています。
標準の Ubuntu 向け xremap では `SandS`、仮想修飾キー、変換・無変換の扱いが
同一になる保証はありません。実機検証が必要です。
また `CODE_93` は元設定を維持しており、Ubuntu の IME で日本語入力切替になるとは限りません。

`変換` は F14 の仮想修飾キーに割り当て、`変換 + ,` のみを IME ON 用に使用します。
