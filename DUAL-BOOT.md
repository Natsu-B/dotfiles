# Windows / NixOS デュアルブート（UEFI）

このリポジトリは NixOS 25.11 と `systemd-boot` を使用する。NixOS の ESP は `/boot` にマウントされる。
この設定で管理するのは起動メニューだけであり、Windows のインストールやディスクのパーティション操作は行わない。

## 事前確認

Windows をインストール・再構成する前に重要なデータと EFI パーティションをバックアップする。BitLocker を利用する場合は回復キーも保存しておく。
既存の NixOS の `/boot` やルートパーティションを、Windows インストーラーでフォーマットしないこと。

```sh
findmnt /boot
lsblk -o NAME,SIZE,FSTYPE,PARTTYPE,PARTLABEL,UUID,MOUNTPOINTS
sudo bootctl list
sudo efibootmgr -v
```

Windows が使う EFI System Partition (ESP) が NixOS と同じか、別かを調べる。

## Windows と NixOS が同じ ESP を使用する場合

`/boot/EFI/Microsoft/Boot/bootmgfw.efi` が存在すれば、`systemd-boot` が Windows Boot Manager を自動検出する。
その場合、`boot.loader.systemd-boot.windows` の追加設定は不要。

```sh
sudo ls -l /boot/EFI/Microsoft/Boot/bootmgfw.efi
sudo bootctl list
```

`nixos/configuration.nix` では `boot.loader.timeout = 5;` としているので、起動メニューを 5 秒間表示してから既定のエントリを起動する。
Windows がまだインストールされていない場合、Windows の項目が現れないのは正常。

## Windows が別の ESP を使用する場合

異なる ESP にある Windows は自動検出されない。NixOS 25.11 では `boot.loader.systemd-boot.windows` を使い、EDK2 UEFI Shell で確認したデバイスハンドルを指定できる。
ESP の UUID と `efiDeviceHandle` は別物なので、`lsblk` の UUID をそのまま `efiDeviceHandle` に指定しない。

1. 必要なら、Windows 側の ESP を読み取り専用でマウントし、`EFI/Microsoft/Boot/bootmgfw.efi` があることを確認する（例の UUID は置き換える）。

   ```sh
   sudo mkdir -p /mnt/windows-esp
   sudo mount -o ro /dev/disk/by-uuid/XXXX-XXXX /mnt/windows-esp
   sudo ls /mnt/windows-esp/EFI/Microsoft/Boot/bootmgfw.efi
   sudo umount /mnt/windows-esp
   ```

2. `nixos/configuration.nix` のブートローダー設定に、**一時的に**次を追加する。

   ```nix
   boot.loader.systemd-boot.edk2-uefi-shell.enable = true;
   ```

3. `sudo nixos-rebuild boot --flake .#nixos` を実行して再起動し、`EDK2 UEFI Shell` を選択する。シェルで `map -c` を実行し、各ハンドルを調べる。以下の `FS1` は例であり、実際のハンドルを確認する。

   ```text
   map -c
   ls FS1:\EFI\Microsoft\Boot
   FS1:\EFI\Microsoft\Boot\bootmgfw.efi
   ```

   最後のコマンドで Windows が起動できれば、そのハンドルを使用する。`HD...` ハンドルでも構わない。

4. 検証したハンドルを次の設定に反映する。**`HD0c1` は説明用の例であり、そのまま使わない。**

   ```nix
   boot.loader.systemd-boot.windows."windows-11" = {
     title = "Windows 11";
     efiDeviceHandle = "HD0c1"; # 自分の環境で確認した値へ置換
   };
   ```

5. `sudo nixos-rebuild boot --flake .#nixos` を再実行して再起動し、メニューから Windows と NixOS の両方を起動できるか確認する。検証後は `edk2-uefi-shell.enable` の一時設定を削除できる。

UEFI の構成や接続ディスクが変わったら、ハンドルの再確認が必要になる場合がある。

## 注意事項

- Windows のインストールや更新によって UEFI の起動順序が変更される場合は、ファームウェア設定または `efibootmgr` で NixOS の起動項目を選び直す。
- BitLocker が有効なら、起動経路を変更すると回復キーを求められることがある。キーを確保するまで起動関連の変更をしない。
- `nixos-rebuild boot` は次回起動用の設定を適用する。再起動前にエラーがないことを確認する。
- 同じ ESP の場合も別 ESP の場合も、Windows のシステムファイルを NixOS 側からコピー・移動する必要はない。

参考: [NixOS Wiki: Dual Booting NixOS and Windows](https://wiki.nixos.org/wiki/Dual_Booting_NixOS_and_Windows)
