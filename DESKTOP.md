# Hyprland desktop

## 構成と適用範囲

GDM の既定セッションを Hyprland (UWSM) にし、GNOME は復旧用に残す。
Waybar、Rofi、mako、hyprpaper、hypridle、hyprlock と認証エージェントは
Hyprland セッションだけで起動する。xremap は GNOME / Hyprland 共通の
ユーザーサービスとしてログイン時に起動し、GDM のログイン画面では起動しない。

この変更では `flake.nix` / `flake.lock`、カーネル、開発環境のバージョンを更新しない。
現在の pin に含まれる Hyprland 0.52.2 に合わせて Hyprlang `.conf` を使う。
NixOS 25.11 からのサポート対象リリースへの移行と Lua 化は別の変更として扱う。
`system.stateVersion` と `home.stateVersion` もそのままにする。

## 操作

ここでの英字・数字は JIS キーボードの物理キー位置。Win は Super キー。

| キー | 操作 |
|---|---|
| Win+Space / Win+D | アプリと Action: 登録コマンドを検索 |
| Win+F1 | 実際に登録されている Hyprland のショートカット一覧 |
| Win+F2 | QWERTY / 独自 Programmer Dvorak を切替 |
| Win+V | 履歴を選んでクリップボードにコピー。貼り付けは別途 Ctrl+V |
| Win+Shift+V | 履歴の記録を停止・全消去 / 空の状態から再開 |
| Win+Ctrl+V | 履歴と現在のクリップボードを全消去 |
| Win+Enter | Kitty ターミナル |
| Win+E | ファイルマネージャー |
| Win+L | ロック。履歴も消去 |
| Win+Shift+Q | フォーカス中のウィンドウを閉じる |
| Win+F | 全画面切替 |
| Win+Shift+Space | フローティング切替 |
| Win+矢印 / Win+Shift+矢印 | フォーカス移動 / ウィンドウ移動 |
| Win+1..0 / Win+Shift+1..0 | ワークスペース切替 / 移動 |
| Win+左ドラッグ / Win+右ドラッグ | ウィンドウ移動 / サイズ変更 |
| Win+Shift+M | GDM にログアウト |

Waybar の配列表示をクリックしても配列を切り替えられる。
Clip を左クリックで履歴、右クリックで記録停止・再開。

SandS は Space を離した時に単独の Space を出す。Win+Space は Win を押したまま
Space を押して離す。両キーの離し方で認識されない場合は Win+D を使う。
SandS の感触や実機イベントの取りこぼしはキーボードごとに確認する。

## キーボードの責任分離

XKB は Hyprland / GNOME / Fcitx5 とも **jp (JIS/QWERTY) 固定**。
独自 Dvorak の通常入力と Shift 入力だけを xremap の `exact_match: true`
で変換する。Ctrl / Alt / Win 付きの英数字・記号は入力変換せず、物理的な
JIS/QWERTY 位置を維持する。XKB を別途 us(dvp) に切り替えないこと。

- 独自 Dvorak が初期値。最後に選んだ配列を次回ログインでも使用する。
- Shift+物理数字列 1..0 は、そのまま数字 1..0。
- JIS の ] キーは $ / ~、Yen キーは \\ / |。
- CapsLock / 半角全角は日本語入力切替、Space 長押しは Shift。
- 無変換+I/J/K/L は上/左/下/右、+; は Enter、+O は Delete、+P は Backspace、
  +H は Tab、+U は日本語入力切替、+数字列は数字。
- 数字列変更で失われる % は変換+5 から入力できる。
- QWERTY モードでも SandS、日本語切替、無変換レイヤーは残す。
- xremap 停止時は通常の JIS/QWERTY に戻る。アプリ別フィルターは使わない。

定義は `home/desktop/generate_xremap.py`。ビルド時に生成した JSON/YAML を
`~/.config/xremap/profiles/` に配置する。旧 us(dvp) 前提の定義は `legacy/` に保存し、
現在の設定からは参照しない。

```sh
keyboard-profile status
keyboard-profile qwerty
keyboard-profile dvorak
systemctl --user status xremap.service
journalctl --user -u xremap.service -b
```

選択状態は `${XDG_STATE_HOME:-~/.local/state}/dotfiles/keyboard-profile` に保存。
切替処理は排他制御し、起動失敗時は以前の選択に戻す。GNOME でも Win+F2 と
`keyboard-profile` を使用可能。複数の同一ユーザー GUI セッションの同時使用は想定しない。

## クリップボードの保存方針

[cliphist](https://github.com/sentriz/cliphist) と
[wl-clipboard](https://github.com/bugaevc/wl-clipboard) を利用する。
cliphist の通常のホーム内キャッシュ保存ではなく、必ず次に保存する。

```
$XDG_RUNTIME_DIR/dotfiles-clipboard/db
# 通常は /run/user/1000/dotfiles-clipboard/db
```

`XDG_RUNTIME_DIR` がユーザー所有・0700・tmpfs でない場合は記録を拒否する。
通常ディスクや `~/.cache` への代替保存はしない。ディレクトリは0700、
ファイルの作成権限はユーザーだけに限定。Rofi の検索用キャッシュも同じ一時領域に置く。
テキストのみ、最大100件、1件64KiB。画像は履歴に入れない。

保存場所を変更できる cliphist を採用し、永続保存型マネージャーに暗号化を後付けする
構成は採らない。再起動後までの履歴保持より、データを長く残さないことを優先する。
この構成自体がデータベースを暗号化するわけではない。

wl-clipboard は既存の unstable pin の 2.3.0 を使用し、対応するパスワードマネージャーの
`sensitive` ヒントは除外する。ただし、すべてのアプリがヒントを付けるとは限らない。
パスワード・トークンなどをコピーする前は **Win+Shift+V で記録停止**する。
停止時は履歴、開いている履歴画面、現在の通常/primaryクリップボードを消去する。
再開時も現在のクリップボードを消してから記録するので、停止中にコピーした秘密を
再開直後に取り込まない。

設定済みのロック経路（Win+L、5分アイドル、サスペンド前）は `desktop-lock` を通り、
履歴を消去・停止する。正常に解除した場合だけ、ロック前に記録中なら再開する。
もともと手動停止していた場合は停止のまま。ログアウト、サービス停止、再起動でも
履歴を残さない。直接別のロッカーを起動する場合はこの処理を経由しないので注意する。

履歴画面からは選択した文字列をクリップボードに戻すだけ。自動貼り付け、シェル実行、
同期、クラウド送信はしない。サービスの core dump を無効にし、swap 使用を制限する。

### 保護できない範囲

これは暗号化された秘密保管庫ではない。同じユーザーの悪意あるプロセス、root、
侵害された compositor、RAM の読み出しに対する保護はない。tmpfs は環境によって
swap やハイバネーションに書き出され得る。`MemorySwapMax=0` だけで完全な
非永続化を保証しない。強い保護には swap・ハイバネーション保存先・ディスクの
暗号化方針も確認する必要がある。削除もストレージの安全消去を保証しない。

GNOME ではこの履歴サービスを起動しない。Wayland の clipboard data-control に
依存するため、GNOME の Win+V 履歴までは実装していない。既存の GNOME
clipboard-history 拡張は宣言から外し無効化するが、**過去にその拡張や別ツールが
保存した履歴は自動削除しない**。拡張側の設定から旧履歴を削除し、別の履歴ツールを
並行起動していないことを確認する。

```sh
desktop-clipboard status
desktop-clipboard pause
desktop-clipboard resume
desktop-clipboard clear
systemctl --user status dotfiles-clipboard.service
journalctl --user -u dotfiles-clipboard.service -b
stat -c '%a %U' "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/dotfiles-clipboard"
stat -f -c '%T' "$XDG_RUNTIME_DIR"
```

## アプリ・独自 Action の追加

通常のアプリは `.desktop` ファイルから自動取得する。
`home/desktop/default.nix` の `xdg.desktopEntries` に追加すると同じ検索画面に出る。
例えば、任意のローカルスクリプトを Nix でパッケージした `myCommand` がある場合:

```nix
xdg.desktopEntries.my-action = {
  name = "Action: My command";
  exec = "${myCommand}/bin/my-command";
  terminal = false;
  categories = [ "Utility" ];
};
```

チートシートは `hyprctl -j binds` の description から取得する。`hyprland.conf` では
`bindd` など description 付き定義を使い、一覧の手動二重管理を避ける。

## 壁紙

指定された
[nineish Catppuccin Mocha alt SVG](https://github.com/NixOS/nixos-artwork/blob/master/wallpapers/nix-wallpaper-nineish-catppuccin-mocha-alt.svg)
と同じ絵柄の **公式 PNG 版**を利用する。SVG の描画対応に依存せず、既存 nixpkgs の
`nixos-artwork.wallpapers.nineish-catppuccin-mocha-alt.gnomeFilePath` から取得する。
元画像は既存 pin 内で revision/hash 固定され、ログイン時のネットワーク取得は不要。
Hyprland、ロック画面、GNOME の背景に適用する。

## 導入と確認

作業中ファイルを保存してから、この PR のブランチを取得する。
初回は `update.sh` で他の入力まで更新せず、既存 lock のまま確認する。

```sh
git fetch origin
git switch feat/hyprland-private-desktop
python3 tests/test_desktop.py -v
nix flake check
sudo nixos-rebuild build --flake .#nixos
sudo nixos-rebuild test --flake .#nixos
```

Home Manager の管理対象になる既存ファイルは `.before-hyprland` にバックアップする。
同名バックアップが既に存在する場合は、内容を確認して別名で保管してから再実行する。
Fcitx5 の profile は jp + Mozc に統一するため、独自に追加した入力エンジンがあれば
バックアップと比較する。

`test` が成功したら作業を保存し、一度ログアウト。GDM で Hyprland (UWSM) を選択する。
GDM が前回の GNOME 選択を記憶している場合、既定値変更後でも初回は明示選択が必要。

```sh
hyprctl configerrors
systemctl --user status xremap.service waybar.service dotfiles-clipboard.service
keyboard-profile status
wev
```

Dvorak の文字列・Shift数字列・JIS記号・Ctrl/Alt/Winショートカット、QWERTY切替、
SandS、Mozc、USBキーボード抜き差しを確認する。秘密でないテスト文字列で履歴の
記録・選択・停止・ロック後の消去を確認し、GNOME への再ログインも試す。
問題がなければ `sudo nixos-rebuild switch --flake .#nixos` で永続化する。

入力が壊れた場合は TTY に移り、通常の JIS でログインして:

```sh
systemctl --user stop xremap.service
keyboard-profile qwerty
# 必要に応じてシステム世代も戻す
sudo nixos-rebuild switch --rollback
```

GUI に戻れない場合は再起動して boot menu の以前の NixOS 世代を選ぶ。
GNOME セッション自体は削除していない。

## 検証の範囲

`tests/test_desktop.py` は配列生成、libxkbcommon の実際の jp 定義との照合、
切替失敗の復元、クリップボードの保存先拒否・サイズ制限・秘密ヒント除外・消去・
選択キャンセル・文字列を実行しないこと、シェル構文を検証する。
これは実際の xremap デバイス制御、Hyprland/Rofi 描画、NixOS 評価・ビルドを
代替しない。PR 作成環境には Nix と稼働中の Wayland セッションがないため、
これらの実機確認は上記の手順で行う。
