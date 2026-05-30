# Token Checker

macOS のメニューバーに Claude Code と Codex の使用率を常時表示する macOS アプリケーション。

<p align="center">
  <img src=".github/assets/menubar.svg" alt="メニューバー表示" width="640"/>
</p>

## 概要

ターミナルで `claude login` / `codex login` を完了済みのアカウントに対し、Anthropic の OAuth エンドポイントおよび `codex app-server` の JSON-RPC を経由してレート制限情報を取得する。取得結果はメニューバーに 2 個のドーナツチャートと数値で表示され、クリックでポップオーバーに 5 時間ウィンドウと週次ウィンドウの詳細を展開する。

## 動作要件

| 項目 | 値 |
| --- | --- |
| macOS | 14 Sonoma 以上 |
| Swift | 5.9 以上（Xcode Command Line Tools で可） |
| Claude Code CLI | `claude login` 済み |
| Codex CLI | `codex login` 済み |

Claude Code と Codex のいずれかが欠けていても、もう一方は動作する。

> ⚠️ **`brew install codex`（formula 版）は非対応**
>
> `brew install codex` でインストールされる formula 版は v0.36.0 であり、
> `app-server` サブコマンドが含まれていないため Token Checker は動作しない。
> 必ず `--cask` フラグを付けるか、npm 経由でインストールすること。

## インストール

このリポジトリを clone した上で、自分のマシンでビルドして使うことを前提とする。

```bash
./Scripts/build.sh --install
```

ビルド時に Apple Development の署名 identity が見つからない場合は ad-hoc 署名が自動的に使われる。自分でビルドした `.app` はそのまま起動できる。

インストール後は Finder の「アプリケーション」から `TokenChecker` を開くか、ターミナルから以下を実行して起動する。

```bash
open /Applications/TokenChecker.app
```


## 使用方法

事前にターミナルで以下を実行し、両サービスにログインしておく。

```bash
claude login
codex login
```

いずれもブラウザの OAuth フローを経て、Keychain または `~/.codex/auth.json` にトークンが保存される。アプリは保存されたトークンを参照するため、ログインは CLI 側で 1 度行えばよい。


<p align="center">
  <img src=".github/assets/popover.svg" alt="ポップオーバー表示" width="320"/>
</p>

クリックで展開するポップオーバーには、5 時間ウィンドウと週次ウィンドウの使用率、リセットまでの残時間、更新間隔（30 秒〜10 分、既定 5 分）、ログイン時の自動起動トグルが含まれる。

## データ取得経路

- **Claude**: `/usr/bin/security` 経由で Keychain (`Claude Code-credentials`) から OAuth アクセストークンを取得し、`https://api.anthropic.com/api/oauth/usage` に対して `anthropic-beta: oauth-2025-04-20` ヘッダー付きで GET する。
- **Codex**: `codex` バイナリを子プロセスとして起動し、行区切り JSON-RPC 経由で `account/rateLimits/read` を呼ぶ。バイナリの場所は Homebrew / nodebrew / nvm / volta / asdf / fnm 等の主要なインストール先を順に探索し、見つからない場合はログインシェル経由で `command -v codex` を解決する。`UserDefaults` の `codexPath` キーで手動指定も可能 (`defaults write com.token-checker.app codexPath /abs/path/codex`)。起動コマンドは CLI バージョンに応じて自動的に切り替わる (`codex app-server daemon start` + `codex app-server proxy` 形式と `codex app-server` 単体形式の双方をサポート)。

## アップデート

最新のソースを取得して再ビルドする。

```bash
git pull
./Scripts/build.sh --install
```

既存のアプリは自動的に上書きされる。設定 (ポーリング間隔、ログイン時の自動起動) は UserDefaults に保存されているため引き継がれる。アプリが既に起動中の場合はメニューバーの「終了」で一度落としてから再度開く。

## アンインストール

```bash
killall TokenChecker
defaults delete com.token-checker.app 2>/dev/null
```

## ライセンス

本ソフトウェアは [MIT License](./LICENSE) で配布される。
なお「Anthropic」「Claude」「Codex」は各社の商標であり、本ソフトウェアは Anthropic および OpenAI の公式プロダクトではなく、両社による承認・推奨を受けたものでもない。

## 免責事項

本ソフトウェアは現状有姿 (as-is) で提供されるものであり、動作・安全性・正確性について一切の保証を行わない。本ソフトウェアの利用に起因して発生したいかなる損害 (データ損失、アカウント停止、トークン漏洩、セキュリティインシデント等を含むがこれに限らない) についても、作者は一切の責任を負わない。利用者自身の責任において使用すること。

## 謝辞

UI のデザインは [s-age/ccmeter](https://github.com/s-age/ccmeter)（MIT License）を参考にした。MIT ライセンスは [`LICENSE`](./LICENSE) に同梱している。

<br>

---

<br>

# Token Checker

A macOS menu bar application that displays Claude Code and Codex usage in real time.

## Overview

For accounts already authenticated via `claude login` / `codex login`, this app retrieves rate-limit information through the Anthropic OAuth endpoint and the `codex app-server` JSON-RPC. Results are shown as two donut charts with numeric values in the menu bar; clicking opens a popover with detailed 5-hour and weekly window data.

## Requirements

| Item | Value |
| --- | --- |
| macOS | 14 Sonoma or later |
| Swift | 5.9 or later (Xcode Command Line Tools is sufficient) |
| Claude Code CLI | authenticated via `claude login` |
| Codex CLI | authenticated via `codex login` |

If only one of Claude Code or Codex is available, the other still works.

> ⚠️ **`brew install codex` (Homebrew formula) is NOT supported**
>
> The Homebrew formula installs v0.36.0, which does not include the `app-server` subcommand
> and therefore will not work with Token Checker.
> Use the `--cask` flag or install via npm instead.

## Installation

Clone this repository and build on your own machine.

```bash
./Scripts/build.sh --install
```

If no Apple Development signing identity is found, ad-hoc signing is used automatically. A `.app` you built yourself can be launched directly.

After installation, open `TokenChecker` from Finder's Applications folder, or run:

```bash
open /Applications/TokenChecker.app
```

## Usage

First, log in to both services from the terminal:

```bash
claude login
codex login
```

Each uses a browser-based OAuth flow that saves a token to Keychain or `~/.codex/auth.json`. The app reads the saved tokens, so you only need to log in once via the CLI.

The popover (opened by clicking the menu bar item) shows 5-hour and weekly window utilization, reset countdowns, a refresh-interval picker (30 seconds to 10 minutes, default 5 minutes), and a launch-at-login toggle.

## Data Sources

- **Claude**: retrieves the OAuth access token from Keychain (`Claude Code-credentials`) via `/usr/bin/security`, then issues a GET request to `https://api.anthropic.com/api/oauth/usage` with the `anthropic-beta: oauth-2025-04-20` header.
- **Codex**: spawns the `codex` binary as a subprocess and calls `account/rateLimits/read` via line-delimited JSON-RPC. The binary is discovered by probing common install locations (Homebrew, nodebrew, nvm, volta, asdf, fnm, ...) and falling back to `command -v codex` via the user's login shell. A manual override is available via the `UserDefaults` `codexPath` key (`defaults write com.token-checker.app codexPath /abs/path/codex`). The launch command adapts to the installed CLI version automatically and supports both `codex app-server daemon start` + `codex app-server proxy` (v0.133+) and the single-arg `codex app-server` form (v0.130 and earlier).

## Updating

Pull the latest source and rebuild.

```bash
git pull
./Scripts/build.sh --install
```

The existing app is overwritten in place. Settings (polling interval, launch-at-login) persist via UserDefaults. If the app is already running, quit it from the menu bar item first, then relaunch.

## Uninstall

```bash
killall TokenChecker
defaults delete com.token-checker.app 2>/dev/null
```

## License

Distributed under the [MIT License](./LICENSE).

"Anthropic", "Claude", and "Codex" are trademarks of their respective owners. This software is not an official product of Anthropic or OpenAI, and is not endorsed or approved by either company.

## Disclaimer

This software is provided "as is", without warranty of any kind regarding operation, safety, or accuracy. The author assumes no responsibility for any damages (including but not limited to data loss, account suspension, token leakage, or security incidents) arising from use of this software. Use at your own risk.

## Acknowledgments

The UI design references [s-age/ccmeter](https://github.com/s-age/ccmeter) (MIT License). The full MIT license text is included in [`LICENSE`](./LICENSE).
