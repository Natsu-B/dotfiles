# macOS を保管先、NixOS を作業用コピーにする

macOS の `~/data/` にデータを永続保存し、指定した相対パスのファイル・ディレクトリだけ NixOS の `~/work/` 以下に置く。Mac の `~/data/<path>` は NixOS の `~/work/<path>` に対応する。NixOS での編集は、SSH 接続が復旧すると Mac に自動同期される。Linux 上のファイルは同期完了後も**自動削除しない**。

```text
Mac: ~/data/                     NixOS: ~/work/
├── project-a/       <====>     ├── project-a/
├── project-b/  (対象外)         │
├── documents/                   └── documents/
│   ├── report.pdf  <====>          └── report.pdf
│   └── notes/ (対象外)
└── datasets/ (対象外)
```

Mutagen の `two-way-safe` を使用する。これは「Mac を優先する」モードではなく、双方の編集を反映し、危険な競合を記録するモード。**削除操作も同期される**ので、Mac 側には別途バックアップ（Time Machine など）が必要。

## 1. NixOS の準備

`nixos/configuration.nix` では、SSH を Tailscale インターフェース `tailscale0` からだけ受け付け、パスワードログインを禁止する。既存の `services.tailscale.enable = true` と `programs.nix-ld.enable = true` は変更しない。

**`nixos-rebuild switch` より先に**、Mac の *公開* SSH 鍵を NixOS ユーザー `hotaru` の `~/.ssh/authorized_keys` に登録すること。秘密鍵はコピーしない。

Mac 上で公開鍵を表示：

```sh
cat ~/.ssh/id_ed25519.pub
```

鍵がない場合は Mac で `ssh-keygen -t ed25519` を実行する。NixOS にローカルログインして、公開鍵を1行として `~/.ssh/authorized_keys` に追記する。

```sh
install -d -m 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
vim ~/.ssh/authorized_keys  # Mac の公開鍵を1行追加
sudo nixos-rebuild switch --flake .#nixos
sudo tailscale status
```

`tailscale status` が未接続を示す場合は `sudo tailscale up` で初期設定する。`sshd` は NixOS ホストで動く。`codex-usb` VM の SSH 設定とは無関係。

## 2. macOS の準備

Mac と NixOS を同じ Tailscale ネットワークに接続する。Mac の `~/.ssh/config` に以下を追加する（IP は NixOS 側の `tailscale ip -4` で確認する）。

```sshconfig
Host nixos
    HostName 100.x.y.z
    User hotaru
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    BatchMode yes
```

接続確認：`ssh nixos true`。macOS に Mutagen を入れて、ログイン時にデーモンを起動する。

```sh
brew install mutagen-io/mutagen/mutagen
mutagen daemon register  # macOS の自動起動登録（Mutagen では実験的機能）
mutagen daemon start

mkdir -p ~/.local/bin
install -m 755 scripts/mac-data-sync ~/.local/bin/mac-data-sync
```

最後の `install` はこのリポジトリのルートディレクトリで実行。`~/.local/bin` を `PATH` に通すか、フルパスで呼び出す。

## 3. 必要なファイルやディレクトリだけ同期

Mac 側にデータを置き、Mac からセッションを開始する。**Mac 側の保存先が存在しない場合、スクリプトは作成せず中止する**。

```sh
mkdir -p ~/data/project-a
mac-data-sync start project-a               # ディレクトリ全体
mac-data-sync start documents/report.pdf    # 既存の単一ファイル
mac-data-sync status project-a
```

作業時は Linux の `~/work/project-a` や `~/work/documents/report.pdf` を編集する。Mac の Mutagen デーモンと SSH が使えるときに変更が同期され、切断中も Linux で編集できる。Mac の `~/data` 全体を複製する必要はない。

`mac-data-sync start project-a/src` のようにサブディレクトリだけ指定することもできる。ただし **`project-a` と `project-a/src` のような親子パスを同時に同期しない**。同じファイルを複数セッションが管理すると、競合や不整合の原因になる。

指定は `~/data` からの相対パス。各パス要素には英数字・ピリオド・アンダースコア・ハイフンのみを使用できる（`..` や絶対パスは不可）。既存の通常ファイル・ディレクトリのみを許可し、シンボリックリンクそのものを同期ルートにはできない。指定したファイル・ディレクトリは開始前にMac側で用意し、`start` は同じ対象に繰り返し実行しない。

操作：

```sh
mac-data-sync list                # セッション一覧
mac-data-sync status project-a    # 状態と競合を確認
mac-data-sync flush project-a     # 同期を明示的に実行
mac-data-sync pause project-a     # 一時停止。ファイルは残る
mac-data-sync resume project-a    # 自動同期を再開
mac-data-sync terminate project-a # 同期を終了。双方のファイルは削除しない
```

`MAC_DATA_ROOT=/Volumes/External/data` と `MAC_DATA_REMOTE=nixos` でそれぞれ保存先の親ディレクトリと SSH 接続先エイリアスを変更可能。

## 4. Linux 側のコピーが不要になったら

同期中の `rm -r` は Mac 側のデータも削除しうる。自動削除処理は用意しない。Linux 側だけを明示的に削除する場合は、**Mac 上で同期を完了し、競合や接続エラーがないことを確認してから**セッションを終了する。

```sh
mac-data-sync flush project-a
mac-data-sync status project-a
# Mac の ~/data/project-a に編集結果があることを確認
mac-data-sync terminate project-a
# この後、必要な場合だけ Linux 側で実行
ssh nixos 'rm -ri ~/work/project-a'
```

`terminate` は同期セッションを終了するだけで、両側のファイルは削除しない。次回は `mac-data-sync start project-a` で同期を作り直す。Linux 側の削除を望まなければ、何もしなければよい。

## 注意

- `two-way-safe` の `safe` は削除禁止ではない。同期対象内での通常の削除も他方へ反映される。Mac のスナップショット／バックアップを利用する。
- 既に両側に異なる内容のファイルがある場合は、同期前に状態を確認する。競合が発生したら `mac-data-sync status` で確認する。`flush` だけで競合解消を保証しない。
- `.git` など VCS 管理ディレクトリは `--ignore-vcs` で同期しない。Linux で Git が必要なら独立して用意する。`target` や `node_modules` などの巨大なビルド生成物は、プロジェクトごとに `mutagen sync create --ignore=...` で除外を検討する。
- Linux の空き容量は選択したファイル・ディレクトリ分と同期時の一時領域が必要。**容量に応じた自動退避・削除はしない**。
- 「Wi-Fi 接続時だけ」を判定しているわけではない。Mac が起動して Mutagen と SSH/Tailscale が利用可能なら、利用中のネットワークにかかわらず同期する。
- macOS の `~/data` 自体は NixOS の Home Manager 管理対象外。Linux の dotfiles は SSH の受け口を提供し、同期セッションは Mac 上で管理する。

参考：[Mutagen synchronization](https://mutagen.io/documentation/synchronization)、[SSH endpoints](https://mutagen.io/documentation/transports/ssh/)、[Daemon](https://mutagen.io/documentation/introduction/daemon/)。
