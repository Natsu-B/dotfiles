# Hyprland + DankMaterialShell

## 構成

NixOS / Home Manager を 26.05 に更新し、Hyprland 0.55.4 の Lua 設定を使う。
`flake.lock` は Nix が解決した revision / narHash をコミットしている。
DMS は既存の unstable pin の 1.6.2 と、その同じ pin の Quickshell を組み合わせる。
Hyprland と画面共有 portal はともに stable のパッケージを使う。

GDM の既定は Hyprland (UWSM)、GNOME は復旧用として維持する。
バー、アプリ・Action 検索、通知、音声、ネットワーク、Bluetooth、ディスプレイ設定、
壁紙、電源メニューを DMS にまとめる。Waybar / mako / hyprpaper / hyprpolkitagent
の個別サービスは起動しない。DMS / clipboard / hypridle は `graphical-session.target` から起動し、`XDG_CURRENT_DESKTOP=Hyprland` の条件で GNOME では起動しない。停止・セッション判定には実際の UWSM target `wayland-session@hyprland.desktop.target` を使う。UWSM target は `graphical-session.target` より前なので、そこから DMS を直接 WantedBy にすると ordering cycle になる。

例外として、機密性に関わる部分は既存の実装を維持する。
Win+V の履歴は cliphist + Rofi、実際の画面ロックは hyprlock。
DMS のロック操作も `desktop-lock` に転送し、履歴の停止・消去を必ず経由する。
DMS のアイドル時間は GUI で変更できる。hypridle は logind とサスペンドの橋渡しだけに使い、
独立したアイドルタイマーは設定しない。

`system.stateVersion = "24.05"` と `home.stateVersion = "25.11"` は変更しない。
カーネル、Codex USB、開発環境の構成方針と、他の flake 入力の pin は維持する。
ただし stable の更新に伴う各パッケージのバージョン変更はある。

## 操作

Win は Super。英字・数字のショートカットは JIS キーボードの物理位置。

| キー | 操作 |
|---|---|
| Win+Space / Win+D | DMS のアプリ・Action 検索 |
| Win+I | DMS 設定 |
| Win+P | DMS のディスプレイ設定（配置・複製など） |
| Win+A | DMS クイック設定 |
| Win+N | 通知 |
| Win+X | 電源メニュー |
| Win+F1 | DMS の Hyprland ショートカット一覧 |
| Win+F2 | QWERTY / 独自 Programmer Dvorak の切替 |
| Win+V | 一時保存の履歴からコピー。貼り付けは別途 Ctrl+V |
| Win+Shift+V | 履歴を停止・全消去 / 空の状態から再開 |
| Win+Ctrl+V | 履歴と現在のクリップボードを全消去 |
| Win+L | ロックし、履歴も停止・消去 |
| Win+Ctrl+F5 | DMS を再起動 |
| Win+Enter / Win+E | Kitty / ファイルマネージャー |
| Win+Shift+Q | ウィンドウを閉じる |
| Win+F / Win+Shift+Space | 全画面 / フローティング切替 |
| Win+矢印 / Win+Shift+矢印 | フォーカス移動 / ウィンドウ移動 |
| Win+1..0 / Win+Shift+1..0 | ワークスペース切替 / ウィンドウを送る |
| Win+左ドラッグ / Win+右ドラッグ | ウィンドウ移動 / サイズ変更 |
| Win+Shift+M | UWSM を終了し GDM に戻る |
| Print | DMS の領域スクリーンショット |

SandS は Space を離す際に単独 Space を送る。Win+Space は Win を押したまま Space を離す。
認識されない離し方の場合は Win+D を使う。DMS が起動しない場合も Win+Enter / Win+L は
DMS を経由しない。`hypr-cheatsheet` で Rofi の復旧用一覧も開ける。

Win+P は設定画面を開くキーであり、押すだけで複製へ切り替えるキーではない。
複製可能なモード、スケーリング、接続先の相性は実機で確認する。
DMS で選んだ画面配置は次項のローカルファイルに保存し、リビルドは不要。

## GUI の変更を残す仕組み

Nix で管理するのは入力・キー操作・基本外観・プログラムのパス。
次の通常ファイルは初回だけ生成し、その後は DMS の GUI で編集する。

```
~/.config/DankMaterialShell/settings.json
~/.local/state/DankMaterialShell/session.json
~/.config/hypr/dms/outputs.lua
~/.config/hypr/dms/layout.lua
~/.config/hypr/dms/colors.lua
~/.config/hypr/dms/cursor.lua
~/.config/hypr/dms/windowrules.lua
```

リビルド・ログインで表示設定や選択した壁紙を上書きしない。
ロック・ログアウト・アプリ起動の共通コマンドだけは毎回反映し、古い Nix store パスを残さない。
JSON が壊れている場合は黙って初期化せずエラーにする。バックアップから修復するか、
DMS を止めて該当ファイルを別名保存し `desktop-dms-config` を実行する。

唯一、`~/.config/DankMaterialShell/clsettings.json` は Nix 管理の読み取り専用ファイル。
DMS 内蔵の永続クリップボード記録を無効にするためで、GUI から有効化しないこと。

Lua の編集場所は次のとおり。

```
home/desktop/hypr/hyprland.lua  # 読み込み順
home/desktop/hypr/input.lua     # jp 固定の入力設定
home/desktop/hypr/appearance.lua
home/desktop/hypr/binds.lua     # description 付きキー定義
home/desktop/dms.nix           # GUI 初期値・DMS 起動・commands.lua の生成
home/desktop/packages.nix      # 補助プログラム
nixos/desktop.nix              # GDM / UWSM / GNOME / portal / Zoom
```

旧 `.conf` は `legacy/hyprland-0.52.conf` に退避し、現在の設定からは読み込まない。
DMS の標準 binds も読み込まない。Win+V、SandS、配列切替との重複を避けるためである。

## キーボード

XKB は GNOME / Hyprland / Fcitx5 とも **jp 固定**。
独自 Dvorak の通常入力と Shift 入力だけを xremap の `exact_match: true` で変換する。
Ctrl / Alt / Win 付きは JIS/QWERTY の物理位置のまま。DMS や GNOME の GUI から
XKB を us(dvp) に変えると二重変換になるため、切替には Win+F2 を使う。

初期値は独自 Dvorak。選択状態を `~/.local/state/dotfiles/keyboard-profile` に保存する。
Shift+物理数字列は数字 1..0、JIS の ] は $ / ~、Yen はバックラッシュ / 縦棒。
CapsLock / 半角全角は Fcitx5 の既定トリガー `Zenkaku_Hankaku` として日本語入力を切り替える。Space 長押しは Shift。
無変換+I/J/K/L は上下左右、+; は Enter、+O は Delete、+P は Backspace、
+H は Tab、+U は `Zenkaku_Hankaku`（日本語入力切替）、+数字列は数字。変換+5 は %。
QWERTY モードでも SandS、日本語切替、無変換レイヤーは維持する。

定義は `home/desktop/generate_xremap.py`。選択変更を排他制御し、xremap の起動失敗時は
以前の選択に戻す。xremap は両デスクトップのログイン時に一つだけ起動し、GDM では起動しない。
同一ユーザーでの複数 GUI セッション同時使用は想定しない。

```sh
keyboard-profile status
keyboard-profile qwerty
keyboard-profile dvorak
systemctl --user status xremap
```

## 日本語入力

Fcitx5 の日本語エンジンは Karukan のみを使い、Mozc はインストールしない。
Karukan 本体は `nixos/karukan.nix` で upstream の不変 commit に固定し、同梱の llama.cpp を
`GGML_OPENVINO=ON` でビルドする。NixOS の Intel NPU ドライバも有効にし、ログイン環境では
`GGML_OPENVINO_DEVICE=NPU`、stateless 実行を指定する。

通常の1候補 greedy 変換は NPU を優先する。複数候補の beam search は同じ Karukan/Jinen の
CPU instance で実行する。NPU モデルのロードまたは greedy 推論が失敗した場合も、Karukan 内部で
同じ GGUF の CPU instance に即時再実行し、その model instance では以後 CPU を使う。
別 IME への切替は行わない。

モデルは Jinen v2 small / xsmall の Q4_K_M。Hugging Face の repository 名だけでなく
40桁 revision まで固定する。Karukan に追加した `repo@revision` 解釈により、初回取得は
ネットワークを使うが mutable な `main` は追わない。取得後は Hugging Face cache を使う。
`max_latency_ms=0` とし、初回の NPU graph compile の遅さだけで light model に固定降格しない。

実機では次を確認する。

```sh
ls -l /dev/accel/accel0
journalctl --user -b | grep -Ei 'karukan|openvino|npu'
```

## クリップボードとロック

[cliphist](https://github.com/sentriz/cliphist) と
[wl-clipboard](https://github.com/bugaevc/wl-clipboard) を使用する。
履歴は必ず `$XDG_RUNTIME_DIR/dotfiles-clipboard/db` に置き、ユーザー所有・0700・tmpfs
を確認する。条件に合わなければ停止し、通常ディスクへの代替保存は行わない。
Rofi の検索キャッシュも同じ一時領域。テキストのみ最大100件、1件64KiB。
選択内容はコピーするだけで、自動貼り付け・シェル実行・同期は行わない。

wl-clipboard 2.3.0 が伝える sensitive ヒントを除外するが、全アプリが付与するわけではない。
秘密をコピーする前は Win+Shift+V で停止する。停止・再開時には現在の通常/primary
クリップボードも消去し、停止中の秘密を再開直後に取り込まない。

DMS のメニュー、Win+L、アイドルロック、サスペンド前のロックは `desktop-lock` に集約する。
履歴を止めて消去し、hyprlock が正常終了した場合だけ logind に解除を通知する。
ロック前に記録していた場合だけ再開する。ロック失敗時は停止を維持し警告する。
DMS のロック用カスタムコマンドを別のロッカーに変更するとこの保証は失われる。

**暗号化された秘密保管庫ではない。** 同じ UID の悪意あるプロセス、root、侵害された
compositor、RAM 読み出しを防ぐものではない。tmpfs も swap / ハイバネーションに
書き出され得る。core dump 無効化と `MemorySwapMax=0` だけで完全な非永続化や
安全消去を保証しない。強い保護にはディスク・swap・休止領域の暗号化方針も必要。

DMS 内蔵履歴は disabled=true にするが、DMS 自体は空のキャッシュ DB を作成し得る。
過去に DMS / GNOME 拡張 / 別ツールが保存した履歴は自動消去しない。
既存の履歴を確認し、別の記録機能を同時に有効にしないこと。
GNOME セッションでは今回の Win+V 履歴は起動しない。

```sh
desktop-clipboard status
desktop-clipboard pause
desktop-clipboard resume
desktop-clipboard clear
stat -c '%a %U' "$XDG_RUNTIME_DIR" "$XDG_RUNTIME_DIR/dotfiles-clipboard"
stat -f -c '%T' "$XDG_RUNTIME_DIR"
```

## ChatGPT デスクトップ

公式 Linux アプリは Wayland セッションでも既定では XWayland を使う。内蔵ディスプレイは
fractional scale を使うため、XWayland ではぼやけ・倍率ずれが出やすい。また Chromium/Electron
の XWayland 経路では Fcitx の preedit が不安定になる。

そのため dotfiles の `chatgpt` wrapper は
`--enable-features=UseOzonePlatform --ozone-platform=wayland --enable-wayland-ime`
を常時付け、native Wayland で起動する。倍率を `--force-device-scale-factor` で固定しないので、
DMS でモニター倍率を変えてもアプリ側が追従できる。

確認:

```sh
hyprctl clients | grep -A8 -i 'chatgpt'
fcitx5-remote -n
```

## Zoom と画面共有

Home Manager の単体 `pkgs.zoom-us` ではなく、NixOS の `programs.zoom-us.enable` を使い、
有効なデスクトップに対応する依存関係を付ける。portal 設定は小文字の `hyprland`。
ScreenCast / Screenshot は Hyprland、FileChooser は GTK、GNOME では GNOME 用を使う。

これは Zoom のすべての Wayland 機能を保証する修正ではない。
会議前にモニター共有・ウィンドウ共有・共有停止・再共有を確認する。
デスクトップ版で問題がある場合に比較できるよう、ランチャーに Zoom Web も登録する。
ブラウザでも失敗するなら portal / PipeWire 側、Zoom だけならアプリ側を優先して切り分ける。

```sh
systemctl --user status xdg-desktop-portal xdg-desktop-portal-hyprland pipewire wireplumber
journalctl --user -b -u xdg-desktop-portal -u xdg-desktop-portal-hyprland
```

## 壁紙・独自 Action

指定の [nineish Catppuccin Mocha alt](https://github.com/NixOS/nixos-artwork/blob/master/wallpapers/nix-wallpaper-nineish-catppuccin-mocha-alt.svg)
と同じ絵柄の公式 PNG を、nixpkgs の固定済み artwork パッケージから使う。
DMS の初期壁紙は `~/.local/share/backgrounds/nix-nineish-mocha-alt.png` を参照する。
以後 GUI で変更可能。GNOME / hyprlock の既定壁紙にも同じ画像を使う。

DMS は通常の `.desktop` アプリと独自 Action を検索する。
`home/desktop/default.nix` または `dms.nix` の `xdg.desktopEntries` に追加する。

```nix
xdg.desktopEntries.my-action = {
  name = "Action: My command";
  exec = "${myCommand}/bin/my-command";
  terminal = false;
  categories = [ "Utility" ];
  settings.NotShowIn = "GNOME;";
};
```

## 適用と復旧

作業を保存し、現在の設定・生成をバックアップしてから実行する。
初回は `update.sh` で他入力まで更新せず、コミット済み lock をそのまま使用する。

```sh
git fetch origin
git switch feat/hyprland-private-desktop
git pull --ff-only
python3 -m unittest discover -s tests -v
nix flake check
sudo nixos-rebuild build --flake .#nixos
sudo nixos-rebuild test --flake .#nixos
```

Home Manager は新しく管理する既存ファイルを `.before-hyprland` に退避する。
同名バックアップが既にある場合は内容を確認して別名保管する。Fcitx5 の独自設定も確認する。
`test` は次回起動の既定を変更しないが、現在のサービスやホーム設定は変更する。
テスト中の表示セッションが切れる可能性があるため、会議・作業の途中で実施しない。

一度ログアウトし、GDM から Hyprland (UWSM) を選ぶ。
OS / compositor / Qt 更新を含むため、既存セッションの reload だけで済ませない。

```sh
hyprctl version
hyprctl configerrors
systemctl --user status dms xremap dotfiles-clipboard dotfiles-hypridle
keyboard-profile status
```

配列・Karukan（NPU/CPU fallback）・SandS・USB hotplug、Win+V とロック消去、ディスプレイの複製・拡張・抜き差し、
Zoom の共有、GNOME への再ログインを実機で確認する。成功後に永続化して再起動する。

```sh
sudo nixos-rebuild switch --flake .#nixos
sudo reboot
```

問題時は GDM で GNOME を選ぶ。入力が壊れたら TTY で `systemctl --user stop xremap`
を実行すると通常の JIS/QWERTY に戻る。DMS だけなら `systemctl --user restart dms`。
システムを戻す場合は次を使うか、起動メニューから直前の NixOS generation を選ぶ。

```sh
sudo nixos-rebuild switch --rollback
```

GUI が書いた DMS 設定は generation のロールバックでは元に戻らない。
必要に応じて DMS を停止し、バックアップした settings.json / session.json / dms/*.lua を戻す。

## 検証範囲

CI でコミット済み lock の一致、Python 回帰テスト、NixOS 全体の評価、Lua の61個の
キー定義の展開・重複・説明・呼出先、pin した Hyprland の `--verify-config` を実行する。
Lua チェックの実行コマンド文字列だけはダミーであり、アプリ起動や画面共有の実機テストではない。
補助スクリプトと DMS パッケージのビルド、実際の xremap による生成プロファイル検証も行う。
CI の成功は OS 全パッケージのビルドや、実機の GPU / ロック / Zoom の成功を意味しない。
