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

## Sleep は S4（ハイバネーション）

P14s Gen 5 は通常の suspend が s2idle（S0）で、S3 は提供されない。
sleep・蓋閉じ・サスペンドキーを S4 に統一する。DMS のアイドル時の動作も
Hibernate を初期値とするが、自動休止の時間は従来どおり 0（無効）から変更しない。
ドックや外部画面使用中の蓋閉じは従来どおり無視する。

`/var/lib/hibernate.swap` に 40 GiB を確保する。systemd が UEFI の
HibernateLocation に swap のデバイスと位置を保存し、systemd initrd が復帰する。
固定の `resume_offset` は使わない。`systemctl suspend` を使うアプリにも対応するため、
upstream の suspend ユニットの依存関係を維持し、実行する処理を hibernate に変更する。

S4 はディスクへの保存・復元が必要なので、通常の suspend より休止・復帰に時間がかかる。
現在のルートディスクは暗号化されていないため、休止イメージも暗号化されない。

新しいカーネルへ切り替える場合は、休止する前に通常の再起動を行う。
ビルド済みの構成は、次のコマンドで現在のセッションを変更せず次回起動へ予約できる。

```sh
sudo bash /home/hotaru/dotfiles/scripts/stage-s4.sh --apply
```

作業を保存して通常の再起動を行った後、`swapon --show` の 40 GiB の swap と
DMS の休止機能が利用可能なことを確認する。実際の S4 / 復帰は、端末から
`systemctl hibernate` を実行して検証する。現状のビルド・ハードウェア確認と、
実際の休止・復帰の完了は区別する。

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
CapsLock / 半角全角は従来どおり xremap の `CODE_93` で日本語モードを切り替える。Space 長押しは Shift。
無変換+I/J/K/L は上下左右、+; は Enter、+O は Delete、+P は Backspace、
+H は Tab、+U は日本語入力切替、+数字列は数字。変換+5 は %。
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
通常の入力はOpenVINOを有効にしてGPUを優先する（`GGML_OPENVINO_DEVICE=GPU`）。
NPUを使う場合は `GGML_OPENVINO_DEVICE=NPU` を指定する。NPUが利用できない場合は、
モデルのロード前にGPUへ切り替える。CPUへの再推論は追加しない。
GPUは `GGML_OPENVINO_STATEFUL_EXECUTION=1`、NPUはbackendの固定形状経路を使う。
NPUではこのstateful設定は参照されず、GPUへ切り替わった場合に有効になる。

Karukan upstreamは `fbe9927548b75435bd43410aaaad742e39f579c8` に固定する。
`KanaKanjiConverter::from_source` → `LlamaCppModel::from_file` → `from_file_with_n_ctx`
はupstreamで `.with_n_gpu_layers(0)` を指定するため、その固定だけを外して
`LlamaModelParams::default()` を使う。固定済みllama-cpp-2 / llama-cpp-sys-2 0.1.157の
既定は `n_gpu_layers=-1`、出力層を含む全層offload要求である。
環境変数とbackend有効化だけでは、upstreamの層数指定は変わらない。
`KanaKanjiConverter` はupstreamのまま、独自accelerator選択やCPU fallbackは追加しない。

`strategy = "main"` のgreedy top-1を使い、残りの候補は学習・辞書・かな/カナで埋める。
`live_conversion = false` と `candidate_window = "conversion"` でもupstreamは入力中に
推論していたため、`refresh_input_state` の共通処理で止めてSpaceで推論する。
live conversionや入力中の候補表示を明示した場合の推論は維持する。
main strategyではlight modelをロードせず、推論失敗は `Karukan conversion failed` として記録する。

日本語入力では `c` を `k` と同じキーとして扱う。`ca/ci/cu/ce/co` は
「か/き/く/け/こ」、`cya` は「きゃ」、`cca` と `cka` は「っか」。
英字直接入力とShiftによる一時英字入力は変更しない。
Spaceで変換候補を表示した後は、次の文字キーを押すと選択中の候補を確定し、
その文字から新しい入力を始める。Enterは不要。候補移動・取消・カーソル編集・
Ctrl/Alt操作は従来どおりで、live変換の表示中に毎文字を自動確定する動作ではない。
live変換はキー処理中に同期推論するため、GPUへ変更しても待ちは残る。
GPUはNPUより短い待ちを確認しており、live変換で使う場合もGPUを優先する。
2026-10-02の同一実機・モデルで `nihongo` を各3回live変換した試験では、
待ちが発生した12キーの中央値はNPU約1.77秒、GPU約0.30秒。
文字入力にかかった累積待ちはNPU約6.6〜7.0秒、GPU約1.2〜1.3秒で、双方3回とも「日本語」。
GPUでも約300msの同期待ちが残るため、引っかかりを完全に解消する変更ではない。

NixOS 26.05 stable上で、OpenVINO 2026.4 / oneTBB / OpenCL / Level Zeroは固定済みunstableを使う。
NPUのカーネルドライバは `hardware.cpu.intel.npu.enable = true` で維持する。
Intel公式のユーザードライバとNPUコンパイラ1.38.0をhash固定で追加し、Fcitxのlibrary pathへ
含める。`ZE_ENABLE_ALT_DRIVERS` でこのドライバを選ぶ。既存1.28ドライバとコンパイラの
組み合わせでは変換誤りを再現したため、そのまま使用しない。
同梱llama.cppの旧 `NPU_COMPILER_DYNAMIC_QUANTIZATION` はOpenVINO 2026.4が拒否するので除く。
NPUの `CacheMode::OPTIMIZE_SIZE` も必要なメタデータがないため除く。
コンパイルキャッシュには `GGML_OPENVINO_COMPILED_MODEL_CACHE_DIR` を使う。

2026-10-02、Core Ultra 9 185H / Intel Arc / Meteor Lake NPU、small Q4_K_Mで実機検証した。
最終版は5入力を各3回、NPU・GPUとも正しく変換できた。Space待ちはNPU約1.47〜2.96秒
（中央値2.20秒）、GPU stateful約0.29〜1.67秒（中央値0.31秒）。
入力中にはモデル推論が走らないことも確認した。
NPUは `/dev/accel/accel0` と新ドライバのロード、GPUはDRM compute時間増加を確認した。
これは独立プロセスからFcitx addonのFFIを呼んだ測定で、画面表示までの遅延ではない。
NPU使用でもモデル準備などのCPU処理は残り、CPU負荷ゼロや非同期変換を保証しない。
電力比較は中断したため、省電力順位は確定していない。

GPUへの切替は「NPUがデバイス一覧にない場合」に限る。NPU推論途中の失敗をGPUで
自動再実行する処理はない。NPUWの演算単位GPU切替は実機で誤変換を起こしたため採用しない。
推論失敗が続く場合はGPUを指定して再起動する。

### 独立した実機試験

`scripts/karukan-benchmark.py` は稼働中のFcitxを変更せず、ローカルGGUFと同じ場所の
`tokenizer.json` を使う。一時設定で学習を無効にし、`BENCH_FRESH_ENGINE=1` で
変換結果キャッシュを避ける。`BENCH_REQUIRE_CORRECT=1` は5入力の期待値・AI候補・
入力中の推論停止を検証する。GPU初回コンパイルは温まったキャッシュと区別する。
`BENCH_LIVE=1` はlive変換でキーごとの待ちを測る。この場合、入力中の推論停止は検証しない。
`BENCH_C_ALIAS=1` は明示変換でc/k・促音・直接英字の表示を検証し、
5入力のkをcに置き換えてAI変換も確認する。
`BENCH_TYPE_TO_COMMIT=1` は明示変換で候補を移動した後、次の文字入力で
選択候補が確定し、新しい入力が始まることを検証する。

```sh
repo="$PWD"
ov_package=$(nix build --impure --no-link --print-out-paths --expr \
  "builtins.head (builtins.getFlake \"path:$repo\").nixosConfigurations.nixos.config.i18n.inputMethod.fcitx5.addons")
# 単独実行にもFcitxと同じ実行環境を渡す。
export LD_LIBRARY_PATH=$(nix eval --impure --raw --expr \
  "builtins.concatStringsSep \":\" (map (p: \"\${p}/lib\") (builtins.head (builtins.getFlake \"path:$repo\").nixosConfigurations.nixos.config.i18n.inputMethod.fcitx5.addons).extraLdLibraries)"):/run/opengl-driver/lib
export ZE_ENABLE_ALT_DRIVERS=$(nix eval --impure --raw --expr \
  "(builtins.getFlake \"path:$repo\").nixosConfigurations.nixos.config.environment.variables.ZE_ENABLE_ALT_DRIVERS")
BENCH_PACKAGE="$ov_package" BENCH_MODEL="/absolute/path/to/model.gguf" \
  BENCH_LOG=/tmp/karukan-npu.log BENCH_FRESH_ENGINE=1 BENCH_REQUIRE_CORRECT=1 \
  GGML_OPENVINO_DEVICE=NPU GGML_OPENVINO_STATEFUL_EXECUTION=1 \
  GGML_OPENVINO_COMPILED_MODEL_CACHE_DIR=/tmp/karukan-npu-compiled \
  python3 scripts/karukan-benchmark.py > /tmp/karukan-npu.jsonl
```

GPU比較は `GGML_OPENVINO_DEVICE=GPU` と別のコンパイルキャッシュを指定する。
CPU専用比較を行う場合だけ、addonに `.override { openvinoSupport = false; }` を指定する。
OpenVINO有効時は層数0でも演算offloadがあるため、CPU専用比較として扱わない。

モデルは Jinen v2 small / xsmall の Q4_K_M。Hugging Face の repository 名だけでなく
40桁 revision まで固定する。Karukan に追加した `repo@revision` 解釈により、初回取得は
ネットワークを使うが mutable な `main` は追わない。取得後は Hugging Face cache を使う。
`max_latency_ms=0` は残すが、既定の main strategy では adaptive 判定自体を使わない。

Fcitx5 が Karukan を選択できても、addon の共有ライブラリが読み込めなければ
入力イベントは Karukan エンジンへ届かない。llama.cpp / ggml は
`libkarukan_fcitx5.so` へ静的リンクし、Cargo の一時的な
`libllama.so.N` / `libggml*.so.N` を Fcitx の実行時依存にしない。
OpenVINO / oneTBB / OpenCL は通常の共有依存として Nix store から解決する。
静的な ggml-openvino の CMake link interface は Cargo へ伝播しないため、
実際に Fcitx が dlopen する `karukan.so` へ
`openvino::runtime` / `openvino::threading` / `OpenCL::OpenCL` を明示リンクする。
`ldd -r karukan.so` で `not found` だけでなく `undefined symbol` も検出し、
また llama / ggml の動的依存が残る場合もビルド自体を失敗させる。

実機では次を確認する。

```sh
clinfo -l
ls -l /dev/dri/renderD*
ls -l /dev/accel/accel0
journalctl --user -b | grep -Ei 'karukan|openvino|gpu|npu'
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

配列・Karukan（GPU優先、NPU選択可）・SandS・USB hotplug、Win+V とロック消去、ディスプレイの複製・拡張・抜き差し、
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
