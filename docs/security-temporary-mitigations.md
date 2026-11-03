# セキュリティ対策と復旧管理台帳

Draft PR の変更は **mainに適用済みとは扱わない**。更新と復旧は毎回、固定リビジョンのパッケージ定義・バックポート・キャッシュ・実行時依存を確認してから別PRで行う。自動マージはしない。

## 対策状況（2026-11-03）

| 対象 | 状態 | 現在の判断・必要な次の作業 |
| --- | --- | --- |
| Anki: GHSA-932p-crhj-v43p / GHSA-jw6j-j4mf-8jgm | **26.09.3を維持** | 上流の修正済み下限は26.9。PR #15の25.09.4へのダウングレードを撤回し、導入Ankiが26.9未満にならないようCIで検査 |
| Brotli: CVE-2026-111497 / GHSA-9v8h-qqgm-4m35 | **未解決、実行時到達性は要検証** | locked stableは1.2.1、unstable/masterは1.2.0。全域overlayは再ビルドが多すぎるため不採用。上流の修正済みパッケージとバイナリキャッシュを確認後に必要な入力のみ更新 |
| Expat: CVE-2026-113351 / 115506 / 117610 / 118370 | **未解決、悪用経路は要検証** | 3系統とも2.9.0。上流2.10.0または4件のバックポートを確認後、対象入力の更新候補を作成 |
| glib-networking: CVE-2026-103963 / GHSA-xwh2-f88c-v27r | **未解決、TLSクライアントの到達性は要検証** | 3系統とも2.80.1。上流2.90.1または該当修正のバックポートと互換性を確認後に限定更新 |
| [PR #14](https://github.com/Natsu-B/dotfiles/pull/14) | **mainにマージ済み** | Nix CI Action、Gemini CLI、Tailscaleの既存セキュリティ修正は保持。旧版へ無条件に戻さない |
| [PR #15](https://github.com/Natsu-B/dotfiles/pull/15) | **Draft・防止策のみ** | Ankiのバージョン下限・セキュリティ版の一覧確認・高コストの再ビルドを抑えるCI。Brotli/Expat/glib-networkingの脆弱性そのものは未修正 |

### 一次情報
- [Anki: 外部パスからのコード実行](https://github.com/ankitects/anki/security/advisories/GHSA-932p-crhj-v43p) / [Anki: internal APIへの到達](https://github.com/ankitects/anki/security/advisories/GHSA-jw6j-j4mf-8jgm)
- [BrotliのGHSA](https://github.com/advisories/GHSA-9v8h-qqgm-4m35) / [Brotli 1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1)
- [Expat 2.10.0の変更履歴](https://github.com/libexpat/libexpat/blob/R_2_10_0/expat/Changes)
- [glib-networkingの修正MR](https://gitlab.gnome.org/GNOME/glib-networking/-/merge_requests/288)

**注記:** パッケージバージョンの文字列だけでは、ベンダーによるバックポートの有無や、実際の攻撃経路は判断できない。CIのバージョン出力は調査用であり、修正済みの認定ではない。

## PR #15で撤回した暫定実装

| 提案 | 元の設定と撤回内容 | 理由・復旧状況 |
| --- | --- | --- |
| unstable/master全体のBrotli overlay | `flake.nix`を元の`legacyPackages`に復旧 | Desktop entriesのビルド予定が20件から631件に増加し120分でキャンセル。mainには未適用 |
| CI制限を360分まで延長 | 延長を取り消し、PRでは90分を上限に設定 | 大量再ビルドを隠さないため。mainには未適用 |
| `system.replaceDependencies`でBrotliをシステム全体で置換 | `nixos/configuration.nix`から削除 | IFDを伴い`nix flake check --no-build`が`references.nix.drv`で失敗。mainには未適用 |
| `unstable.anki` 26.09.3を`pkgs.anki` 25.09.4に変更 | **`home/home.nix`を元に戻す** | 25.09.4に上記の高リスクGHSAが残る。mainには未適用 |

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
