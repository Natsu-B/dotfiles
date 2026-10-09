# Windows 11 + NixOS 25.11: 完全再インストール（同一ディスク / UEFI）

この手順は **既存の Windows/NixOS をすべて削除して入れ直す** 場合のもの。重要なデータと復旧キー、Windows のライセンス情報を事前に控える。対象ディスクを取り違えるとデータが失われる。

Windows を Rufus の USB から先にインストールし、**Windows 用に確保した部分以外を未割り当て**にする。その後 NixOS Live ISO から `systemd-repart` を使って、Windows のパーティションはそのままに NixOS 用の領域を作る。

## ディスク構成（例）

| 領域 | ファイルシステム | 用途 |
| --- | --- | --- |
| Windows が作成する ESP | FAT32 | Windows Boot Manager + systemd-boot（共用） |
| Windows が作成する MSR | なし | Windows 管理用 |
| Windows 本体 | NTFS、例: 128 GiB | Windows のみ |
| Windows が作成する Recovery | Windows が管理 | WinRE |
| NIXOS_BOOT | FAT32、4 GiB | XBOOTLDR: NixOS のカーネル/initrd |
| NIXOS_ROOT | ext4、残り | NixOS の `/` |

Windows の自動生成パーティションの個数・順序・容量は Windows のバージョンで変わり得る。ESP が小さくても NixOS の世代を保存できるよう、別の XBOOTLDR を使う。`nixos/windows-dualboot.nix` が `/efi` と `/boot` を設定する。

## 1. Windows 11 を Rufus から入れる

1. 公式の Windows 11 ISO を入手し、Rufus で **GPT / UEFI（CSM なし）** の USB インストーラーを作る。NixOS 用 ISO は別の USB を用意する。
2. Rufus の Windows User Experience では、必要に応じてローカルアカウント用の設定やプライバシー項目を選ぶ。Rufus 自体は Windows の標準アプリを削除する debloater ではない。TPM/Secure Boot 要件を不要に回避しない。
3. Windows Setup を UEFI モードで起動し、対象内蔵ディスクの既存パーティションを削除する。**別ディスクや USB を削除しない**。
4. 未割り当て領域から「新規」を選び、Windows 用に例えば **131072 MiB (128 GiB)** を指定する。Windows Setup が作る ESP / MSR / Recovery を維持したまま Windows をインストールする。
5. **残りの未割り当て領域は Windows のボリュームにしない**。Windows を起動して初期設定を終え、デバイス暗号化/BitLocker の状態と回復キーを確認する。Fast Startup/休止状態の無効化も検討する。

Windows 11 の公称ストレージ最小要件は 64 GB だが、更新や一時ファイルの余裕を考えて 128 GiB を目安にする。ドライバーや Windows 固有アプリの容量に応じて調整する。

## 2. NixOS Live ISO で空き領域を自動分割

**注意:** `disko` の標準的なディスク構成適用はディスク全体を再初期化するため、Windows インストール後の同一ディスクに使用しない。このリポジトリは `systemd-repart` で未割り当て領域だけに NixOS 用パーティションを追加する。

1. NixOS ISO を UEFI モードで起動。現在の設定は署名付き Secure Boot 対応ではないため、必要ならファームウェア側で Secure Boot を無効化する。BitLocker 回復キーは必ず保持する。
2. GitHub の PR を merge 済みなら `main`、未 merge の検証なら `feat/windows-dual-boot` を clone する。

   ```sh
   git clone -b feat/windows-dual-boot https://github.com/Natsu-B/dotfiles.git
   cd dotfiles
   lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,PARTLABEL,MODEL,MOUNTPOINTS
   ls -l /dev/disk/by-id/
   ```

3. **対象 SSD の by-id を自分で確認してから**、次のコマンドを実行する（以下のパスはそのまま使わず書き換える）。

   ```sh
   sudo bash installer/prepare-windows-dualboot.sh /dev/disk/by-id/nvme-REPLACE_WITH_REAL_DISK
   ```

   このスクリプトは GPT/UEFI・単一 ESP・Windows Boot Manager・NTFS の存在を確認し、既存 NixOS パーティションがある場合は停止する。まず `systemd-repart --dry-run=yes` で予定を表示し、`CREATE-NIXOS` と入力した場合のみ実際に作成する。

   宣言的な割り当ては `installer/repart.d/10-xbootldr.conf`（FAT32 4 GiB）と `20-root.conf`（ext4 残り、最低 80 GiB）が担当する。成功すると次のマウントが作成される。

   ```text
   /mnt       -> NIXOS_ROOT (ext4)
   /mnt/boot  -> NIXOS_BOOT (FAT32 XBOOTLDR)
   /mnt/efi   -> Windows ESP (FAT32)
   ```

   デバイスが複数ある場合や既存 Windows の構成が異なる場合は、警告を無視して進めない。スクリプトは実機での検証が済むまでは試験的なものとして扱う。

## 3. dotfiles から NixOS をインストール

**既存の `install.sh` はインストール済み NixOS の構成反映用**なので、Live ISO からの新規インストールには使用しない。

ディスクをマウントしたまま、Live ISO で次を実行する。

```sh
# Clone した dotfiles を新しい /home にコピー。
sudo mkdir -p /mnt/home/hotaru
sudo cp -a . /mnt/home/hotaru/dotfiles

# 実際の /mnt のマウント構成からハードウェア設定を再生成する。
sudo nixos-generate-config --root /mnt --show-hardware-config | \
  sudo tee /mnt/home/hotaru/dotfiles/nixos/hardware-configuration.nix > /dev/null

# Flake は Git 管理下のファイルを評価するため、更新を stage する。
sudo git -C /mnt/home/hotaru/dotfiles add nixos/hardware-configuration.nix

# 専用の Windows デュアルブート設定を指定する。
sudo nixos-install --flake '/mnt/home/hotaru/dotfiles#nixos-windows'

# 初回ログインできるようユーザーパスワードを設定する。
sudo nixos-enter --root /mnt -c 'passwd hotaru'
sudo nixos-enter --root /mnt -c 'chown -R hotaru:users /home/hotaru/dotfiles'
```

パスワード設定を終えたら再起動し、NixOS と Windows の両方が systemd-boot メニューから起動することを確かめる。

## 4. 再インストール後の管理

- `nixos-windows` は既存の `nixos` Flake 出力を変更しない専用構成。`nixos/windows-dualboot.nix` は `/etc/dotfiles-nixos-flake-profile` に出力名を記録し、`update.sh` が `nixos-windows` を使って再ビルドする。
- 新しい `hardware-configuration.nix` の UUID はこのマシンに固有。インストール後、差分を確認してコミット・同期する。元の UUID をそのまま復元しない。
- Windows と systemd-boot が同じ ESP にあるので、Windows の起動エントリは自動検出され、`boot.loader.systemd-boot.windows` の手動ハンドル設定は不要。
- Secure Boot を再び有効化するなら、NixOS 側でも適切な署名付き起動設定を別途整える。
- PR のブランチからインストールした場合は、PR の main へのマージ後にローカルの Git 履歴と hardware-configuration の変更を整理してから `git pull` する。

参考: [NixOS Dual Boot Wiki](https://wiki.nixos.org/wiki/Dual_Booting_NixOS_and_Windows) / [systemd-repart(8)](https://www.freedesktop.org/software/systemd/man/latest/systemd-repart.html) / [Rufus FAQ](https://github.com/pbatard/rufus/wiki/FAQ)
