# RTX830 L2TP/IPsec (NixOS)

RTX830 の L2TP/IPsec リモートアクセス VPN を NixOS の NetworkManager から利用する。
接続先、PSK、ユーザー名、パスワード、社内/学内 LAN のネットワーク情報は **Git に置かない**。
元の Ubuntu / Arch 向けスクリプトの `install` や `setup` は NixOS では使用しない。

## 導入（初回）

このリポジトリの `nixos/rtx830-vpn.nix` が NetworkManager-l2tp、IKEv1 対応の
strongSwan、xl2tpd、ppp、および接続用の `rtx830-vpn` コマンドを導入する。
NixOS 26.05 の標準 NetworkManager-l2tp は脆弱なため、上流の修正済み 1.52.6
をリリース成果物の SHA-256 を検証して使う。IKEv1 は互換性のため明示的に有効化する。

```sh
cd ~/dotfiles
sudo nixos-rebuild test --flake .#nixos
# 問題がなければ恒久反映する
sudo nixos-rebuild switch --flake .#nixos
```

## 接続プロファイルの登録（この PC だけ）

```sh
nm-connection-editor
```

1. VPN → L2TP を新規作成し、接続名を **`rtx830-vpn`** にする。
2. Gateway に配布されたサーバーのホスト名または IPv4 アドレスを入力する。
3. Username / Password に配布されたユーザー資格情報を設定する。
4. IPsec を有効にし、配布された PSK を設定する。
5. PPP の認証は MSCHAPv2 を許可し、PAP / CHAP / MSCHAP / EAP は無効にする。
6. 必要なら IPsec の IKE / ESP アルゴリズムを RTX830 側の設定に合わせる。
   従来の配布設定が要求する古い AES/SHA-1/DH2 方式は強度が低いため、
   **ルータ管理者が許可した接続先に限って**使用する。PFS の有無も合わせる。
7. 自動接続を無効にし、パスワードと PSK を **全ユーザー用の接続として安全に保存**する。
   ファイルの権限が `root:root` / `0600` であることを確認する。

> [!IMPORTANT]
> デフォルトの接続ボタンから直接 VPN を ON にしないこと。
> 接続先アドレスが PPP peer アドレスと一致する RTX830 では、VPN パケットが
> VPN 自身へ流れるルーティングループが起き得る。必ず次のコマンドで接続する。

## 接続 / 切断

```sh
rtx830-vpn check       # プロファイルと VPN 接続前の経路を確認
sudo rtx830-vpn up     # サーバー宛の物理経路を固定してから接続（必要ならパスワードを尋ねる）
rtx830-vpn status      # 状態確認
sudo rtx830-vpn down   # 切断して経路を解除
```

`up` は既存の物理回線を確認し、接続先の宛先だけをルーティングテーブル 193、
優先度 110 のポリシールールで固定する。既存のルールと競合する場合は接続を中止する。
`up` に失敗した場合、および NetworkManager から `vpn-down` が通知された場合は
設定した一時経路を解除する。ルータ側の設定・接続先情報は変更しない。

VPN パスワードが NetworkManager のシステム接続に保存されていない場合は、
`up` が端末上で対話的に入力を求める。秘密情報をコマンド引数や Git に書かないこと。

Tailscale の exit node 等が有効で、接続先への経路が別のトンネルを通る場合も
安全のため接続を中止する。経路衝突がある場合は Tailscale を確認する。

接続対象の LAN だけを VPN に通す場合は、プロファイルの IPv4 経路で
「この接続をネットワーク上のリソースにのみ使用する」を設定し、
**管理者から配布された CIDR のみ**を静的経路として追加する。
既定では全通信が VPN 経由になり、Tailscale など他の VPN と競合し得る。

## 診断

```sh
journalctl -b -u NetworkManager --no-pager
journalctl -b -u NetworkManager-dispatcher --no-pager
nmcli -f GENERAL.STATE connection show rtx830-vpn
ip -4 rule show
ip -4 route show table 193
```

ログや診断結果にはサーバー名・アドレスが含まれる可能性があるため、
外部へ貼り付ける前に伏せる。資格情報は共有しない。

## 保守・安全上のメモ

- 変更前: `nixos/configuration.nix` に L2TP クライアントはなく、Tailscale のみ有効。
- 導入理由: RTX830 の IKEv1/L2TP と PPP peer 由来の経路ループへの対策。
- 暫定対策: `strongswan` の IKEv1 有効化と、NixOS 26.05 の脆弱な
  NetworkManager-l2tp 1.52.0 を上流修正済み 1.52.6 で置換。
- 解除条件: RTX830 側が IKEv2 などの新しい VPN に移行したら IKEv1/L2TP 一式を撤去。
  また nixpkgs が修正版 NetworkManager-l2tp を提供したら、個別のバージョン固定を削除する。
- ルータ情報とシークレットは `/etc/NetworkManager/system-connections/` の
  root 専用プロファイルのみに保存し、Flake や Nix store に含めない。

参考:

- [NixOS networkmanager-l2tp パッケージ](https://github.com/NixOS/nixpkgs/blob/nixos-26.05/pkgs/by-name/ne/networkmanager-l2tp/package.nix)
- [NetworkManager-l2tp 1.52.6 リリース](https://github.com/nm-l2tp/NetworkManager-l2tp/releases/tag/1.52.6)
- [NetworkManager dispatcher のイベント仕様](https://networkmanager.dev/docs/api/latest/NetworkManager-dispatcher.html)
