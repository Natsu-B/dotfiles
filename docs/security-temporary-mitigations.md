# セキュリティ対策と復旧管理台帳

Draft PR の変更は **mainに適用済みとは扱わない**。更新と復旧は毎回、固定リビジョンのパッケージ定義・バックポート・キャッシュ・実行時依存を確認してから別PRで行う。自動マージはしない。

## 対策状況（2026-11-04）

| 対象 | 状態 | 現在の判断・必要な次の作業 |
| --- | --- | --- |
| Anki: GHSA-932p-crhj-v43p / GHSA-jw6j-j4mf-8jgm | **26.09.3を維持** | 上流の修正済み下限は26.9。PR #15の25.09.4へのダウングレードを撤回し、導入Ankiが26.9未満にならないようCIで検査 |
| Brotli: CVE-2026-111497 / GHSA-9v8h-qqgm-4m35 | **未解決、実行時到達性は要検証** | locked stableは1.2.1、unstable/masterは1.2.0。全域overlayは再ビルドが多すぎるため不採用。上流の修正済みパッケージとバイナリキャッシュを確認後に必要な入力のみ更新 |
| Expat: CVE-2026-113351 / 115506 / 117610 / 118370 | **Codex DesktopとClaude Desktopの直接リンクの修正をCI再検証中** | 3系統とも2.9.0。2アプリの直接依存に上流2.10.0を適用（nixpkgs PR #582242のソースhash）。他の依存先、バンドル版、間接参照は未対策の可能性あり |
| glib-networking: CVE-2026-103963 / GHSA-xwh2-f88c-v27r | **未解決、TLSクライアントの到達性は要検証** | 3系統とも2.80.1。上流2.90.1または該当修正のバックポートと互換性を確認後に限定更新 |
| [PR #14](https://github.com/Natsu-B/dotfiles/pull/14) | **mainにマージ済み** | Nix CI Action、Gemini CLI、Tailscaleの既存セキュリティ修正は保持。旧版へ無条件に戻さない |
| [PR #15](https://github.com/Natsu-B/dotfiles/pull/15) | **Draft・限定的な暫定修正** | Ankiの下限・大量ビルド防止に加え、2アプリの直接依存Expatだけ2.10.0に更新。Brotli・glib-networking、他のExpat利用者は未修正 |

### 一次情報
- [Anki: 外部パスからのコード実行](https://github.com/ankitects/anki/security/advisories/GHSA-932p-crhj-v43p) / [Anki: internal APIへの到達](https://github.com/ankitects/anki/security/advisories/GHSA-jw6j-j4mf-8jgm)
- [BrotliのGHSA](https://github.com/advisories/GHSA-9v8h-qqgm-4m35) / [Brotli 1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1)
- [Expat 2.10.0の変更履歴](https://github.com/libexpat/libexpat/blob/R_2_10_0/expat/Changes)
- [glib-networkingの修正MR](https://gitlab.gnome.org/GNOME/glib-networking/-/merge_requests/288)

**注記:** パッケージバージョンの文字列だけでは、ベンダーによるバックポートの有無や、実際の攻撃経路は判断できない。CIのバージョン出力は調査用であり、修正済みの認定ではない。

## Expatの暫定対策・復旧条件

- 対象：`home/home.nix`, `home/app/codex-desktop.nix`, `home/app/claude-desktop.nix`。
- 変更前：両アプリとも`pkgs.expat` (2.9.0)に直接依存。変更後：両アプリに`secureExpat` (2.10.0)を明示的に渡す。`pkgs`全体はoverrideしない。
- 根拠：[上流Expat 2.10.0](https://github.com/libexpat/libexpat/releases/tag/R_2_10_0)と[nixpkgs PR #582242](https://github.com/NixOS/nixpkgs/pull/582242)で採用されたソースハッシュ。**システム全体への適用ではない**。
- 検証：CIで2アプリの選択Expatバージョンを評価し、ビルド後ELFの修正版優先をCIで検査する。実機の`ldd`/ストア閉包およびアプリへの入力経路は要検証。既存ライブラリ経由で旧Expatが残る可能性を排除していない。
- 復旧条件：固定nixpkgsの`pkgs.expat`が4件の修正を含む2.10.0以上（または修正を全てバックポート）に更新され、バイナリキャッシュ・2アプリのビルド・起動・ELF依存を確認できたとき。この時は`secureExpat`と明示的引数だけを削除し、元の`pkgs.callPackage ... { }`に戻す復旧PRを作成。**安全性の保証がない状態で暫定対策を取り除かない**。

## PR #15で撤回した暫定実装

| 提案 | 元の設定と撤回内容 | 理由・復旧状況 |
| --- | --- | --- |
| unstable/master全体のBrotli overlay | `flake.nix`を元の`legacyPackages`に復旧 | Desktop entriesのビルド予定が20件から631件に増加し120分でキャンセル。mainには未適用 |
| CI制限を360分まで延長 | 延長を取り消し、PRでは90分を上限に設定 | 大量再ビルドを隠さないため。mainには未適用 |
| `system.replaceDependencies`でBrotliをシステム全体で置換 | `nixos/configuration.nix`から削除 | IFDを伴い`nix flake check --no-build`が`references.nix.drv`で失敗。mainには未適用 |
| `unstable.anki` 26.09.3を`pkgs.anki` 25.09.4に変更 | **`home/home.nix`を元に戻す** | 25.09.4に上記の高リスクGHSAが残る。mainには未適用 |

## Expatの実リンク先修正（2026-11-09、追加検証待ち）

- **検出した不具合:** [Desktop configuration run 42437775605](https://github.com/Natsu-B/dotfiles/actions/runs/42437775605) は全CIが成功したが、`desktop-app-builds` のログにおいて、Codex DesktopとClaude Desktopの双方で `autoPatchelfHook` が `libexpat.so.1` を **Expat 2.9.0** から選択していた。2.10.0を `buildInputs` に追加しただけでは意図した対策にならない。
- **変更前:** 両アプリのELFが `libexpat.so.1 -> ...-expat-2.9.0/lib` と解決され、CIはその内容を表示するだけだった。
- **修正:** `home/app/codex-desktop.nix` と `home/app/claude-desktop.nix` では `postFixup` の処理が後続の `postFixupHooks`（autoPatchelf）で上書きされていたため、全fixup完了後の `postPhases` にRPATH修正を移動し、`libexpat.so.1` を直接必要とするELFのRUNPATH先頭に修正版 `lib.getLib expat` を設定する。他のRUNPATHは維持し、`patchelf` を明示的に導入する。
- **回帰防止:** `.github/workflows/desktop-checks.yml` で両アプリの全ELFを調べ、直接 `libexpat.so.1` を必要とする実行ファイルのランタイム探索順序が **Expat 2.10.0** を最初に選ぶことを必須条件にした。期待パスは複数出力パッケージの `-dev` ではなく共有ライブラリの `out` を検査する。以前のように未修正でも成功する検査には戻さない。
- **検証条件:** 修正後の3ジョブが成功し、Expat実リンク検査でも2.10.0が先頭となることをログで再確認する。バンドル版・静的リンク・`dlopen` の利用はこの検査の範囲外であり、修正済みと断定しない。
- **復旧:** 固定nixpkgsと実行時の全対象が修正済みとなり、アプリビルド・動作を検証したうえで、暫定的なRUNPATH修正と `secureExpat` をともに削除する復旧PRを作成する。

## PR #15 CIジョブ分割（2026-11-08）

- **元の設定:** `.github/workflows/desktop-checks.yml` の単一ジョブで評価・Desktop checks・NixOS全体のビルドを実施し、90分で一律終了。
- **観測した原因:** [Desktop configuration run 41745844683](https://github.com/Natsu-B/dotfiles/actions/runs/41745844683) では評価・バージョン検査・Desktop entriesが成功したが、NixOS全体の553 derivationsをビルド中に90分制限で停止。中断時は`riscv32-none-elf-gcc`などをソースビルドしていた。大量依存置換の上限600件は超えていない。
- **今回の変更:** 軽量チェックは90分を維持。`full-system-build`を**独立した必須ジョブ**として上限120分で実行し、600件を超える再ビルド予定があれば早期失敗させる。`desktop-app-builds`も必須ジョブに分離し、2つのDesktopアプリ本体をビルドしてELFの直接依存とNix store閉包を出力する。
- **適用対象と制約:** GitHub ActionsのCIに限る。NixOS構成の機能やExpat依存の範囲は変えない。ジョブ成功が実機起動や`dlopen`・バンドルされたExpat全体の安全性を保証するわけではない。
- **解除条件:** 上流キャッシュの改善などにより全システムビルドがチェックと同一90分ジョブ内で安定して完走することを確認できた場合、分離ジョブと120分上限を見直す。無条件に更なる時間延長を行わない。
- **未完了の検証:** 分割後CIの成功確認、実機起動とアプリ側のバンドル・動的ロード検証。これらは合格するまでマージ完了条件として扱わない。

## 既存のその他の暫定対策候補

| 対象 | 元の目的 | 解除条件 |
| --- | --- | --- |
| `nixos/desktop.nix` | xdg-desktop-portal-hyprlandのDMA-BUFバックポート（upstream #427） | pinned版に修正を取り込み、画面共有・スクリーンショットを検証 |
| `nixos/configuration.nix` | Pillow 13 / imageioの`I;16`互換性パッチ | 上流修正と画像処理の回帰検証完了 |

## 安全に恒久修正する手順

1. 最新の対象nixpkgsで修正版本体または修正パッチを確認する。lockリビジョンからバージョンを推測しない。
2. 修正済み入力のみ更新する候補を作る。Ankiは26.9以上を維持し、他のセキュリティ修正を巻き戻さない。
3. 変更前後で以下を比較し、特にQtWebEngine・GLib・カーネルなどのソース再ビルドが増えないか確認する。

   ```sh
   nix flake check --no-build
   nix build --dry-run --no-link .#checks.x86_64-linux.desktop-entries
   nix build --dry-run --no-link .#nixosConfigurations.nixos.config.system.build.toplevel
   ```

4. 可能な範囲でバイナリキャッシュから取得し、CIと実行時閉包（静的リンク・バンドル版を別途含む）を確認する。未解決の脆弱性を修正済みとして報告しない。
5. 上流修正で不要となった暫定回避策だけを削除する**復旧PR**を作り、当時の設定・削除理由・検証・復旧PR番号・解除日時をここに残す。

### 修正を適用できない間の緩和
不明な出所のAnkiデッキや添付物、Brotliストリーム、XMLを開かない。glib-networkingが攻撃者管理のTLSサーバーと通信する経路がある場合は使用を見直す。これらは更新の代替ではなく、個別のアプリ到達性を確認する。
