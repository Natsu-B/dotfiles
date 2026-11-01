# 一時的なセキュリティ対策と復旧管理

このファイルは、上流の修正を取り込めるまでの一時的な対策を記録する。脆弱性が上流で解消されても、**ロックされた入力の更新、ビルド結果、実行時依存関係を確認するまでは**暫定対策を削除しない。

| ID | 状態 | 導入日 | 対象 | 暫定変更 | 元の設定 | 解除条件 |
| --- | --- | --- | --- | --- | --- | --- |
| CVE-2026-111497 / GHSA-9v8h-qqgm-4m35 | 暫定対策・要実機検証 | 2026-11-01 | `flake.nix`, `nixos/configuration.nix` | 固定済み stable の Brotli 1.2.1 を unstable/master に overlay で供給し、再 import を統一 | `flake.nix` の `unstable`/`master` は各 `legacyPackages`、`configuration.nix` は対応する input を直接 import | 対象とする pinned unstable/master に Brotli 修正版が入り、必要な rebuild を完了できる |
| CI-BROTLI-2026-11 (CVE-2026-111497 に付随) | 暫定・未検証 | 2026-11-01 | `.github/workflows/desktop-checks.yml` | Desktop configuration ジョブの `timeout-minutes` を 120 から 360 に変更。セキュリティoverlayに伴う追加ビルドを途中で打ち切らず検証するため | `timeout-minutes: 120` | overlayを解除して通常のビルド負荷に戻ったことをCIで確認した後、120分へ復旧。途中で再び上限に達する場合は延長を繰り返さず依存範囲・構成を見直す |

## CVE-2026-111497: Brotli

- [GitHub Security Advisory](https://github.com/advisories/GHSA-9v8h-qqgm-4m35)
- [Google Brotli v1.2.1](https://github.com/google/brotli/releases/tag/v1.2.1)
- 固定済み nixpkgs stable `6f06d204d8f2d8761d9da78778745974a3216381`: `brotli.version = 1.2.1`
- 固定済み nixpkgs unstable `e62746b0b472753ef019baceab6f1e2e52014980`: `brotli.version = 1.2.0`
- master `eca943107b8ccdafb3ca41db9f8bdafcdc45f4a4` にも暫定 overlay を適用。master 側の実際の依存を検証する。
- 上流の影響条件は、細工された Brotli 圧縮ストリームを脆弱なデコーダが展開すること。Anki 等への到達可能性は実機で未検証。

### 解除時の手順

1. `nix flake update nixpkgs-unstable nixpkgs-master` のようなコマンドを無条件に実行しない。更新候補の lock 差分を確認し、必要な入力だけ更新する。
2. `nix eval --raw --expr 'let f = builtins.getFlake (toString ./.); in f.inputs.nixpkgs-unstable.legacyPackages.x86_64-linux.brotli.version'` 等で、**overlay のない上流入力**の Brotli が修正済みであることを確認する。master も同様に確認する。
3. `flake.nix` の `brotliSecurityOverlay`、`patchedUnstable`、master の overlay import を削除し、元の `legacyPackages` を復元する。 `nixos/configuration.nix` 内の `unstablePkgs`/`masterPkgs` については、重複 import を復活させる必要がない限り現行の共有方式を維持する。**無関係な改善は巻き戻さない。**
4. `nix flake check --no-build`、`nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath`、対象プロファイルのビルド、`nix-store -qR` などを使って、Brotli 1.2.0 が残っていないことを検査する。静的リンク・バンドルされた Brotli は別途監査する。
5. 解除は**別のPR**として作成し、暫定対策の行を「解除済み」、解除日時、根拠となる入力 rev、復旧PR番号に更新する。CI と実機適用が確認されるまではマージしない。

### 導入時の検証

```sh
nix flake check --no-build
nix eval --raw .#nixosConfigurations.nixos.config.system.build.toplevel.drvPath
nix build .#nixosConfigurations.nixos.config.system.build.toplevel
nix-store -qR "$(readlink -f result)" | grep -E '/brotli-1\.2\.[01]' || true
```

これらは**実行を要求する検証手順**であり、本PR作成時に成功したという意味ではない。Home Manager のプロファイルも個別に依存閉包を確認する。
