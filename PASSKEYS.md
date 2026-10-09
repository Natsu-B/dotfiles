# Hyprland / Google Chrome の passkey

確認日: 2026-10-08。対象はこの flake の NixOS 26.05 / x86_64-linux、Hyprland UWSM と Home Manager の Google Chrome。

## 設定と対応範囲

`home/home.nix` の Chrome に `--password-store=gnome-libsecret` を追加した。
Hyprland のデスクトップ名に依存せず、既存の GNOME Keyring / Secret Service を Chrome のローカル暗号化用に選ぶ。
これは passkey プロバイダーを追加するフラグではなく、GNOME Keyring 自体が WebAuthn 認証器になるわけでもない。
メニューからの起動も Nixpkgs の Chrome ラッパーを使うため対象となる。

`nixos/desktop.nix` では GNOME Keyring と Bluetooth が既に明示的に有効になっている。
Keyring モジュールは login の PAM 連携を設定し、GDM もこれを利用する。
Hyprland は GDM からパスワードでログインすることを基本とする。
指紋だけでログインした場合、ログインパスワードが渡らず keyring がロックされたままになることがある。
その場合は keyring の解除ダイアログにパスワードを入力するか、パスワードで再ログインする。
既存の fprintd / PAM 設定を変えても、Chrome に指紋による WebAuthn 認証器が追加されるわけではない。

| 方法 | Linux の Chrome での利用条件 |
| --- | --- |
| Google Password Manager（基本の方法） | Chrome のプロフィールへ Google アカウントでサインインし、案内に従って GPM PIN を設定、または既存の Android 画面ロックで解除する。Web サイトへの Google ログインだけでは足りない。 |
| スマートフォンの passkey | Chrome の「スマートフォンまたはタブレット」を選び QR を読み取る。両端の Bluetooth とインターネット接続が必要。通常の Bluetooth ペアリングは不要。 |
| USB FIDO2 セキュリティキー | discoverable credential とユーザー検証をサポートするキーを使い、Chrome でセキュリティキーを選ぶ。必要に応じてキーの PIN とタッチで認証する。U2F 専用キーでは passkey の保存はできない。 |

Chromium の WebAuthn 対応と Google Chrome の Google Password Manager 対応は別物。
Google の限定 API を使う機能を、通常の Chromium / Brave に同じ設定で追加することはできない。
実験的フラグ、TPM 設定、PAM U2F、pcscd、独自の認証デーモンは、この方法には不要。
USB HID の FIDO キーには systemd の標準 `60-fido-id.rules` / `70-uaccess.rules` があり、アクティブなローカルセッションへのアクセスを付与する。
全 hidraw デバイスに権限を広げるルールは追加しない。

## 適用と実機検証

このブランチを取得したリポジトリで実行する。以下の `nixos` は現在の flake のホスト名で、install.sh で変更済みならその名前に置き換える。

```sh
nix flake check --no-update-lock-file
sudo nixos-rebuild build --flake .#nixos --no-update-lock-file
sudo nixos-rebuild switch --flake .#nixos --no-update-lock-file
```

1. Chrome を完全に終了し、GDM からパスワードで Hyprland に再ログインする。
2. 普段の Google Chrome を起動し、`chrome://version` のコマンドラインに `--password-store=gnome-libsecret` があることを確認する。既に起動中の Chrome に接続した場合は新しいフラグが適用されない。
3. 以下で Secret Service の応答を確認する。内容や秘密情報は取得しない。

   ```sh
   busctl --user call org.freedesktop.secrets /org/freedesktop/secrets org.freedesktop.DBus.Peer Ping
   ```

   応答だけでは keyring のロック解除済み状態や passkey 成功までは確認できない。解除要求が出たらログイン keyring のパスワードを入力する。
4. Chrome のプロフィールに Google アカウントでサインインし、Google Password Manager でパスワードと passkey の保存を許可する。テスト用アカウントの passkey 対応 HTTPS サイトで、新しい passkey の保存先に Google Password Manager を選ぶ。GPM PIN の案内を完了し、ログアウト後に passkey で再ログインする。Chrome 再起動後にも確認する。
5. 別の端末の passkey を使う場合は `bluetoothctl show` の `Powered: yes` を確認し、スマートフォン側でも Bluetooth を有効にして Chrome の QR を読む。
6. USB キーを使う場合は接続し、別のテスト用 passkey を登録して再ログインする。認識されないときは対象キーの `/dev/hidrawN` について以下を確認する。

   ```sh
   udevadm info --query=property --name=/dev/hidrawN
   loginctl session-status
   ```

   `ID_FIDO_TOKEN=1`、`uaccess` タグ、およびアクティブなローカルセッションを確認する。
   未登録の機種では標準ルールの認識状況を調べる。root での Chrome 起動や一律 chmod はしない。
   このリポジトリの `codex-usb` VM が USB コントローラーを占有している場合は、キーがホスト側に接続されているかも確認する。

既存プロフィールと keyring のバックアップを確保してから適用する。
保存先変更で既存パスワードが読めなくなった場合は削除・初期化せず、元の設定と keyring の状態を確認する。
GPM の利用にはアカウント・ネットワーク・サイト側の対応が必要で、dotfiles だけではサインインや PIN 設定を自動化できない。
セキュリティキーを紛失・初期化するとキー内の passkey は復元できないため、サイトの復旧手段を維持する。

## この変更の検証結果

- `git diff --cached --check` と `nix-instantiate --parse home/home.nix` は成功。
- `nix flake check --no-update-lock-file` は成功。
- 実際の flake の評価で GNOME Keyring、Bluetooth、login の PAM Keyring 連携がすべて `true` と確認できた。
- Home Manager の Chrome 154.0.8037.97 パッケージをビルドし、`google-chrome` / `google-chrome-stable` ラッパー両方にフラグが含まれることを確認した。
- システムへの適用、ブラウザーのサインイン、passkey の登録・認証、実機の USB / Bluetooth 動作は未実施。上の手順で確認する。

## 参照資料

- [Google Chrome Help: Manage passkeys in Chrome](https://support.google.com/chrome/answer/13168025?hl=en)
- [Google: Passkey support on Android and Chrome](https://developers.google.com/identity/passkeys/supported-environments)
- [Chromium: Linux Password Storage](https://chromium.googlesource.com/chromium/src/+/main/docs/linux/password_storage.md)
- [Chromium: Limiting Private API availability](https://blog.chromium.org/2021/01/limiting-private-api-availability-in.html)
- [GNOME Keyring: パスワードを使わないログイン時の解除](https://wiki.gnome.org/Projects/GnomeKeyring/RunningDaemon)
- [Nixpkgs: 固定済み Chrome ラッパー](https://github.com/NixOS/nixpkgs/blob/825e2028c29b702a4a5f085f08095d12099784f2/pkgs/by-name/go/google-chrome/package.nix)
- [systemd: FIDO デバイス認識](https://github.com/systemd/systemd/blob/main/rules.d/60-fido-id.rules)
- [systemd: アクティブセッションへのアクセス](https://github.com/systemd/systemd/blob/v258/rules.d/70-uaccess.rules.in)
