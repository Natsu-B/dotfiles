# 暫定修正と復旧管理台帳

この台帳は **Natsu-B/dotfiles** の公開済み設定をもとにした暫定対策・既存修正の管理記録です。PRで提案しただけの変更は「適用済み」と扱いません。暫定変更を解除する場合は、lockで固定された入力、上流修正、実際のランタイム閉包、テスト結果を再確認し、**復旧用PR**を作成してください。自動マージしません。

## 脆弱性対策・適用状態

| ID / 関連PR | 状態 | 影響するファイル | 適用方法 | 解除・復旧条件 |
| --- | --- | --- | --- | --- |
| CVE-2026-111497 / GHSA-9v8h-qqgm-4m35 ([PR #15](https://github.com/Natsu-B/dotfiles/pull/15)) | **Draft・未実機検証** | `nixos/configuration.nix` | `system.replaceDependencies.replacements` により、unstable/masterのBrotli 1.2.0の`lib`および`out`への実行時参照を、固定済みstableの1.2.1に差し替える。上流の修正に置換できるまでの一時的なABI互換前提の対処 | pinned unstable/masterに修正済みBrotliが入り、そのパッケージを使うシステム/ホームプロファイルのビルドとランタイム閉包の検証が完了したら置換を削除 |
| CIの再ビルド上限 ([PR #15](https://github.com/Natsu-B/dotfiles/pull/15)) | **提案・恒久的な保護策** | `.github/workflows/desktop-checks.yml` | 120分→90分、desktop-entriesの事前dry-runで100以上の未キャッシュderivationがあれば早期失敗 | CI構成変更時に再評価。単純なタイムアウト延長で重い再ビルドを容認しない |
| CVE-2026-110449 / CVE-2026-110450 / CVE-2026-13745 / TS-2026-014〜017 ([PR #14](https://github.com/Natsu-B/dotfiles/pull/14)) | **mainにマージ済み・恒久対策** | `.github/workflows/desktop-checks.yml`, `home/home.nix`, `home/app/gemini.nix`, `nixos/configuration.nix` | Nix CI action、Gemini CLI、Tailscaleの修正済み版を選択 | **古い脆弱版へ巻き戻さない**。上流変更時も同等以上の安全性を確認 |

## Brotli差し替えの技術的注意

- 修正前のパッケージ版：locked unstable/masterのBrotli **1.2.0**。修正済みの代替：locked stableの **1.2.1**。
- [Google Brotli v1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1) / [GHSA-9v8h-qqgm-4m35](https://github.com/advisories/GHSA-9v8h-qqgm-4m35)。
- NixOS 26.05の公式`system.replaceDependencies`は、出力のストア参照を修正して依存パッケージの**再コンパイルを避ける暫定手段**です。ライブラリの同じ長さの出力名、ABI、ファイル配置が互換であることが前提。libbrotli 1.2.0→1.2.1の実機での動作検証は未了。
- **対象外**：静的リンクやアプリケーション内にバンドルされたBrotli、NixOSのsystem closureに含まれない外部Home Manager / nix profile / Windowsなど。動的な実行時参照以外には効きません。
- CIでNixOSのruntime closureに`brotli-1.2.0`がないこと、および`brotli-1.2.1`があることを検査します。Home Managerの独立したプロファイルや実機の利用パスは別途検査します。
- 旧設定：`system.replaceDependencies.replacements`は未設定、`flake.nix`は各入力の`legacyPackages`を使用。変更の解除時は本項目だけ削除し、他のセキュリティ修正は保持します。

## 過去のPR内で撤回した暫定案

| 項目 | 状態 | 理由・取り消した内容 |
| --- | --- | --- |
| [PR #15](https://github.com/Natsu-B/dotfiles/pull/15) の広域Brotli overlay | **マージ前に撤回** | unstable/masterのパッケージ集合をoverlayした結果、desktop-entriesのビルド予定は20件（PR #14）→**631件**に急増。ランタイム参照差し替え方式へ変更 |
| [PR #15](https://github.com/Natsu-B/dotfiles/pull/15) のCIタイムアウト延長 | **マージ前に撤回** | 120分→360分の暫定延長を廃止。問題のビルド範囲を減らす方針へ変更 |

## 既存の暫定変更候補（セキュリティ脆弱性とは区別）

| 対象 | 現在の措置 | 解除条件 |
| --- | --- | --- |
| `nixos/desktop.nix` | xdg-desktop-portal-hyprlandのDMA-BUF関連バックポートpatch（upstream #427） | pinned portalに上流修正が含まれること、動作確認後にパッチを取り除く |
| `nixos/configuration.nix` | Pillow 13とimageioの`I;16`モード互換性を保つPythonパッケージ拡張 | pinned imageio/関連パッケージの修正と動画・画像処理の動作確認後に削除 |

これらは元の目的を失っていなければ解除しません。「候補」は解除できることを意味しません。

## 検証と復旧PRのルール

1. lockの固定入力で修正済み版に到達したか調べる。単に`flake.lock`のrevが変わっただけでは修正済みとみなさない。
2. `nix flake check --no-build`、`nix build --dry-run --no-link .#nixosConfigurations.nixos.config.system.build.toplevel`、対象プロファイルのビルドを実行。dry-runと実行時間を比較し、大量再ビルドがないことを先に確認する。
3. ビルド後は`nix path-info --recursive .#nixosConfigurations.nixos.config.system.build.toplevel`のBrotliパスを確認。使用アプリ、独立したHome Managerのプロファイル、バンドル済みライブラリも別途調べる。
4. 上流修正で不要になった暫定変更のみを削除して**復旧用PRを作成**。復旧PR番号、解除日、テスト・動作確認の証跡を記録。PRは自動マージしない。
