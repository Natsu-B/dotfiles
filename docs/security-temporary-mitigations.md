# 暫定セキュリティ対策・復旧台帳

この台帳は `Natsu-B/dotfiles` における暫定対策を記録する。**Draft PRの変更はmainに適用済みとは扱わない。** 上流修正後の解除は、固定入力の実際のパッケージ版、再ビルド量、実行時依存、アプリの互換性を検証したうえで別PRにする。自動マージしない。

## 対策の管理

| ID・関連PR | 状態 | 修正内容・元の設定 | 影響・解除条件 |
| --- | --- | --- | --- |
| CVE-2026-111497 / GHSA-9v8h-qqgm-4m35 ([PR #15](https://github.com/Natsu-B/dotfiles/pull/15)) | **暫定案・CI/実機検証待ち** | `home/home.nix`: `unstable.anki` (26.09.3) → `pkgs.anki` (stable 25.09.4)。26.05 stableに含まれるBrotli 1.2.1を使用するAnkiのバイナリ代替を選ぶ。全体overlayもIFD方式も使用しない | **Ankiのバージョンダウン**のため、既存プロファイルの互換性（データベース/アドオン）要確認。将来の `unstable.anki` の関連実行時依存（バンドル版を含む）が修正済みであり、追加の大規模ビルドを生じないと確認した後、別PRで`unstable.anki`に戻す |
| CIで大量ビルドを防ぐ保護 ([PR #15](https://github.com/Natsu-B/dotfiles/pull/15)) | **Draft・検証待ち** | `.github/workflows/desktop-checks.yml`: CI上限120→90分。Desktop entriesのdry-runで未キャッシュのderivationが100件超なら早期失敗 | CIの構成・キャッシュ状況と実測に基づいて閾値を見直す。制限時間を長くすることで問題を隠さない |
| CVE-2026-110449, CVE-2026-110450, CVE-2026-13745, TS-2026-014〜017 ([PR #14](https://github.com/Natsu-B/dotfiles/pull/14)) | **mainにマージ済み・恒久修正** | GitHub Actions Nix、Gemini CLI、Tailscaleの修正済みバージョンへ切替 | 古い脆弱なバージョンへ戻さない。次の変更時は同等以上の安全性を確認 |

## CVE-2026-111497 に対する判断範囲

- [GitHub Security Advisory](https://github.com/advisories/GHSA-9v8h-qqgm-4m35)、[Google Brotli 1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1)。
- 固定 stable `nixpkgs` rev `6f06d204d8f2d8761d9da78778745974a3216381`: Brotli **1.2.1**、Anki **25.09.4**。
- 固定 `nixpkgs-unstable` rev `e62746b0b472753ef019baceab6f1e2e52014980`: Brotli **1.2.0**、Anki **26.09.3**。`nixpkgs-master`側もBrotli 1.2.0。
- AnkiはQtWebEngineなどのライブラリを使用し、Brotliの影響を受ける可能性がある。ただし**具体的な攻撃用入力がAnki上のどの経路でデコーダに到達するか未検証**。
- **今回の変更はAnkiに限定**。ほかのunstable/master依存パッケージ、静的リンク済みBrotli、アプリ内組込み版、他のNixプロファイルは対策されない可能性がある。システム全体のCVE修正とは見なさない。
- 安全性に関する運用上の代償として、Ankiの26.09.3から25.09.4へのダウングレードがある。**現在のAnkiプロファイルをバックアップせずに旧版で開かない**。互換性が確認できない場合はPRをマージしない。

## PR #15 内で撤回した対策・理由

| 提案 | 状態 | 理由 |
| --- | --- | --- |
| `flake.nix`のunstable/master全域を修正済みBrotliでoverlay | **PR内で撤回・main未適用** | Desktop entriesの未キャッシュderivationが20件から631件に増え、120分のCIが途中停止 |
| CIタイムアウトを360分へ延長 | **PR内で撤回・main未適用** | 再ビルド拡大を隠すだけで、利用者のビルド負担が大きい |
| `system.replaceDependencies.replacements`で全システムBrotli参照を書き換え | **PR内で撤回・main未適用** | `nix flake check --no-build`でIFDに必要な`references.nix.drv`を実体化できず評価失敗（[CI #173](https://github.com/Natsu-B/dotfiles/actions/runs/41268054424)）。全システムのストア書き換えにも追加コストと互換性リスクがある |

## 既存の暫定変更候補（CVEとは別）

| 対象 | 導入目的 | 解除条件 |
| --- | --- | --- |
| `nixos/desktop.nix` | xdg-desktop-portal-hyprland DMA-BUF関連パッチ（upstream #427） | pinned packageに修正が含まれ、同じ機能が維持されることを確認後 |
| `nixos/configuration.nix` | Pillow 13 / imageioの`I;16`互換パッチ | 関連パッケージの修正と画像処理動作を確認後 |

上記は自動的に不要になるわけではない。元の変更の理由と解除条件をそれぞれ検証する。

## CI・復旧ルール

1. `nix flake check --no-build`で評価し、破綻があればビルド前に止める。
2. `nix build --dry-run --no-link .#checks.x86_64-linux.desktop-entries`の予定derivation数を確認し、極端な再ビルドを許さない。
3. NixOSのビルド後にAnkiの実行時閉包からBrotli 1.2.0が検出されれば失敗。システム全体の閉包にBrotli 1.2.0が残る場合は警告を出し、**全体対策済みと主張しない**。
4. 上流修正・ロック更新・実行時参照・Ankiプロファイルの互換性を確認し、Ankiの元の入力へ戻す**復旧用PR**を作成。解除日時、再検証結果、PR番号を記録する。
5. PRは自動マージしない。NixOS実機・Ankiの既存プロファイル操作はCIが成功しても別途確認する。
