# Agent Skills (Claude Code / Codex)

この dotfiles の Home Manager は `nodejs`（`npx` 用）、`claude-code`、`codex` CLI、両 Desktop アプリを導入する。
Skill 自体は Nix Store に配置しない。更新可能なユーザーディレクトリ、または各プロジェクトで管理する。

## 現在のプロジェクトだけで使う

```bash
cd /path/to/project
npx skills add vercel-labs/agent-skills \
  --skill web-design-guidelines \
  --agent claude-code --agent codex --copy
```

`-g` を付けないため、インストール対象は現在のプロジェクト。`--copy` で実ファイルを作成し、
`.claude/skills/`（Claude Code）と `.agents/skills/`（Codex）をプロジェクトと一緒に持ち運べる。
Skill と関連ファイルを Git で共有する場合は、それぞれの隠しディレクトリを `git add` する。
リポジトリの `.gitignore` やグローバル除外設定が Skill を除外していないことも確認する。

```bash
git status --short --untracked-files=all
git check-ignore -v .agents/skills/ .claude/skills/ || true
```

ディレクトリ丸ごとのコピーでも、隠しディレクトリと Skill の補助ファイルを含める。
Git clone 先で使いたい場合は、ファイルをコミットしておく必要がある。

## 全プロジェクトで使う

```bash
npx skills add vercel-labs/agent-skills \
  --skill web-design-guidelines \
  --agent claude-code --agent codex --global
```

グローバル Skill は各マシンのユーザーホームに置かれ、プロジェクトのコピーや Git clone には含まれない。
Claude Code は `~/.claude/skills/`、Codex は `~/.agents/skills/` を参照する。
配置先の実際の状態はインストール後に確認する。

## 1セッションだけ使う（永続的なインストール不要）

```bash
npx skills use vercel-labs/agent-skills \
  --skill web-design-guidelines --agent claude-code
```

`skills use` は Skill を一時配置して対応エージェントを起動する。プロジェクトディレクトリにはインストールしない。

## 確認と注意点

```bash
command -v claude
command -v codex
npx skills list       # 現在のプロジェクト
npx skills list -g    # グローバル
```

Skill の認識が更新されないときは、エージェントで Skill を再読み込みするか、新しいセッションを起動する。
また、`npx skills update` が `--copy` で導入した Skill をシンボリックリンクに変更する
事例が報告されている。プロジェクトを移動・共有する場合、更新後の実体とリンク先を確認する。
Skill の内容やスクリプトは実行前に確認し、信頼できる提供元だけを導入する。

参考:
- [Vercel Skills CLI](https://github.com/vercel-labs/skills)
- [Claude Code Skills](https://code.claude.com/docs/en/skills)
- [Codex Skills](https://developers.openai.com/codex/skills)
- [Vercel Skills CLI の `--copy` 更新問題](https://github.com/vercel-labs/skills/issues/1199)
