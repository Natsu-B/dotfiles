# Mac を保存先、NixOS の ~/work を作業用にする

Mac の `~/data` にデータを永続保存し、**NixOS 側のターミナルでファイル一覧を見て選択したものだけ** Linux の `~/work` 以下にコピーする。Linux で編集したファイルは接続復旧時に Mac に自動同期される。同期完了による Linux 側ファイルの自動削除はしない。

```text
Mac: ~/data/                         NixOS: ~/work/
├── project-a/       <============> ├── project-a/      (選択)
├── project-b/                      │                   (未選択)
├── documents/                      └── documents/
│   ├── report.pdf   <============>     └── report.pdf  (選択)
│   └── notes/                                          (未選択)
└── datasets/                                           (未選択)
```

**注意:** Mutagen の `two-way-safe` は「Mac を優先する」モードではなく双方向同期。Linux でファイルを手動削除すると、その削除が Mac にも伝播する。Mac は Time Machine などで別途バックアップする。

## 1. Mac の準備（SSH 接続先）

1. Mac と NixOS を Tailscale の同じ tailnet に参加させる。
2. Mac の **システム設定 → 一般 → 共有 → リモートログイン**を有効にし、アクセスできるユーザーを必要なアカウントに限定する。
3. NixOS ユーザー `hotaru` の **公開** SSH 鍵を、Mac ユーザーの `~/.ssh/authorized_keys` に追記する。秘密鍵はコピーしない。
4. Mac に `~/data` を用意してデータを置く。

NixOS で公開鍵を表示（まだ鍵がなければ `ssh-keygen -t ed25519` で生成）：

```sh
cat ~/.ssh/id_ed25519.pub
```

Mac 側で鍵ファイルの権限を設定し、NixOS の公開鍵を1行追記する：

```sh
mkdir -p ~/.ssh ~/data
chmod 700 ~/.ssh
touch ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys
# エディタなどで NixOS の公開鍵を ~/.ssh/authorized_keys に追記
```

Mac に Mutagen / fzf は不要。Mac のSSHサーバーを公開するため、アクセス範囲、認証方式、Tailscale ACL を適切に制限すること。

## 2. NixOS の準備

NixOS の `~/.ssh/config` に Mac への接続を追加する。Mac の Tailscale IP は Mac の Tailscale 画面などで確認する。

```sshconfig
Host mac
    HostName 100.x.y.z
    User <macOS-user>
    IdentityFile ~/.ssh/id_ed25519
    IdentitiesOnly yes
    BatchMode yes
```

`<macOS-user>` とIPを実際のものに置換する。初回接続時は接続先のホスト鍵を確認する。

```sh
ssh mac 'ls ~/data'
sudo nixos-rebuild switch --flake .#nixos
systemctl --user status mutagen.service
```

このPRで Home Manager から `mutagen`、`fzf`、`mac-data-sync` を導入し、Mutagen のユーザーサービスを設定する。`users.users.hotaru.linger = true` によりログアウト中も NixOS 上のサービスが動作できる。接続は **NixOS → Mac** なので、NixOS 側に新しいSSHサーバー設定は不要。

## 3. NixOS で選択して同期

```sh
mac-data-sync ls       # Mac ~/data 内のファイル・ディレクトリ一覧
mac-data-sync pick     # fzf で検索・複数選択して同期開始
mac-data-sync          # 引数なしでも pick が起動
```

`fzf` では `Tab` で複数選択、`Enter` で決定、`Esc` で中止する。選択後に同期開始の確認が表示される。**ディレクトリを選択した場合、配下のデータ全体が同期対象**になる。Linuxの空き容量を確認すること。

パスを指定して開始することもできる：

```sh
mac-data-sync start project-a
mac-data-sync start documents/report.pdf
mac-data-sync start project-b/src
```

Mac の `~/data/<相対パス>` と NixOS の `~/work/<相対パス>` が対応する。選んでいないものは Linux にコピーされない。既定では一覧表示は4階層まで。深く探すには `MAC_DATA_DEPTH=8 mac-data-sync pick`（最大99）。

同じ親子関係（例：`project-a` と `project-a/src`）を重複同期しないよう、CLIは管理中セッションとの重複を検出して拒否する。初回の既存LinuxデータとMacデータが食い違う場合は競合が発生しうるため、`status` を確認する。

一覧からはVCS管理ディレクトリ（`.git`、`.svn`、`.hg`）を除外し、同期も `--ignore-vcs` を利用する。SSHのパス形式の制約上、`:`、タブ、改行や `..` 要素を含むパスはサポートしない。空白や日本語の名前は利用できる。

## 4. 自動同期と明示的な終了

```sh
mac-data-sync list
mac-data-sync status project-a
mac-data-sync flush project-a
mac-data-sync pause project-a
mac-data-sync resume project-a
```

NixOS が起動してMutagenデーモンが動いており、MacがSSH接続可能なら自動的に同期する。切断中もLinux側の既存ファイルを編集でき、同期が完了してもファイルを自動削除しない。

作業コピーを捨てる場合、**Mac に反映済みで競合がないことを確認してから**同期セッションを終了し、その後でLinux側のコピーを手動削除する。

```sh
mac-data-sync flush project-a
mac-data-sync status project-a
mac-data-sync terminate project-a  # セッションのみ停止。両側のファイルは残る
# Linux側のコピーが不要な場合だけ、自分の判断で削除
rm -ri ~/work/project-a
```

以前のPR版に従い **Mac上で** Mutagenセッションを既に作った場合は、そのセッションを停止・終了してからこの方式に移行する。同じファイルを2つのMutagenセッションから同期させないこと。

## 制約

- 容量に応じたLinux側の自動削除・自動退避はしない。同期に必要なメタデータ・一時ファイルもLinuxの容量を使う。
- Wi-Fi接続時かどうかは判定しない。SSH/TailscaleでMacに到達可能なとき同期する。
- `mac-data-sync` 以外で直接Mutagenセッションを作成・削除すると、重複防止用の状態が古くなることがある。
- Macにある機密ファイルを同期すれば、Linux側にもコピーが残る。同期対象の選択に注意する。

参考：[Mutagen file synchronization](https://mutagen.io/documentation/synchronization)、[Mutagen SSH](https://mutagen.io/documentation/transports/ssh/)、[macOS Remote Login](https://support.apple.com/ja-jp/guide/mac-help/mchlp1066/mac)。
