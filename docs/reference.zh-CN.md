# tmux-remote-linux reference

This is the full Chinese reference manual. For the English version, see [reference.en.md](reference.en.md). For the short setup path, start with [../README.md](../README.md).

`tmux-remote-linux` 是一个用于 AI 编程工具的小型 skill。它通过用户本地已经打开的 tmux pane 操作远程 Linux shell。

有些项目无法在开发者本机完成有效验证。代码在本地，但真正有意义的测试、诊断和确认发生在受限的远端环境里：堡垒机、MFA、跳转脚本、共享机器、私有 kubeconfig、内部数据集，或者本机无法直连的 Kubernetes 集群。

这个工具适合两类典型场景。第一类是远端验证：用户已经手动完成 SSH 登录、切换用户、选择 kubeconfig、准备环境变量等初始化，agent 可以在这个上下文里运行检查命令、测试命令或部署后的验证命令。第二类是线上排障：用户控制进入路径和敏感输入，agent 负责在已授权的终端里读取状态、执行有限命令、分析日志和汇总结论。

Codex 不需要拿到凭据，也不需要自己重新建立 SSH 连接。用户自己登录并准备好 shell；agent 只通过 tmux pane 读取输出、发送命令、汇总结果。

这个项目的目标是**稳妥地代理普通 shell 操作**，不是完整模拟人类使用终端。它有意不追求高交互式命令行和全屏 TUI 的全面支持。非 shell 的交互式 CLI 是另一个平级上下文，不是 shell；即使只是退出，也应该交给拥有该 CLI 的专用 skill。

## 为什么需要这个工具

很多生产环境、内网环境、堡垒机环境不能让通用自动化 agent 直接连接。用户往往已经有一个配置好的终端，里面的登录态、网络、权限和上下文都是正确的。

这个项目把这个终端变成一个很窄的操作通道：

- 读取最近的 pane 输出
- 发送一条命令
- 执行一条短命令，并只返回这条命令的输出和退出码
- 使用前强制选择生产或非生产环境
- 生产环境每条命令都要求人工确认

脚本刻意保持很小。它不管理 SSH 密钥、堡垒机会话、Kubernetes 凭据或服务器资产清单。

## 仓库内容

- `scripts/read.sh`：读取 tmux pane 最近输出。
- `scripts/send.sh`：发送一条命令并按回车。
- `scripts/run.sh`：执行一条短命令，使用 begin/end marker 截取本次输出，并传递远端退出码。
- `scripts/env_guard.sh`：环境选择和生产环境确认的公共保护逻辑。
- `scripts/log.sh`：本地 JSONL 审计日志的公共辅助逻辑。
- `scripts/logs.sh`：查询本地 JSONL 审计日志。
- `SKILL.md`：给 AI 工具使用的安全操作说明。

## 依赖

本机需要：

- macOS、Linux，或 Windows 上的 WSL 环境
- `bash`
- `tmux`
- `base64`
- `awk`、`grep`、`sed`
- `scripts/logs.sh` 查询审计日志时需要本机有 `jq`

macOS 和 Linux 是主要支持环境。Windows 建议使用 WSL，并把 Codex、Claude Code、Gemini CLI、`tmux` 和这个 skill 都安装在同一个 WSL 发行版里。直接在原生 Windows shell、PowerShell 或 Git Bash 中使用没有作为主要目标测试。

远端 pane 里需要：

- 已经可用的 shell prompt
- `run.sh` 需要远端有 `bash`
- 用户已经完成必要的远端初始化，例如登录、切换目录、选择 kubeconfig 等

### 安装 tmux

macOS 推荐用 Homebrew：

```bash
brew install tmux
```

Debian / Ubuntu：

```bash
sudo apt-get update
sudo apt-get install -y tmux
```

RHEL / CentOS / Rocky Linux / AlmaLinux：

```bash
sudo yum install -y tmux
```

如果系统使用 `dnf`：

```bash
sudo dnf install -y tmux
```

安装后确认版本：

```bash
tmux -V
```

## 安装

克隆仓库到任意目录：

```bash
git clone git@github.com:your-org-or-user/tmux-remote-linux.git /path/to/tmux-remote-linux
chmod +x /path/to/tmux-remote-linux/scripts/*.sh
```

脚本可以直接留在克隆目录里使用。不同 AI 工具的接入方式不同：Codex 当前适合把 `SKILL.md` 和 `scripts/` 安装到自己的 skills 目录；Claude Code、Gemini CLI 等工具可以用一个指针文件引用这个目录里的 `SKILL.md`。

### Codex

Codex 需要把 `SKILL.md` 和脚本放到自己的 skills 目录：

```bash
mkdir -p "$HOME/.codex/skills/tmux-remote-linux"
cp /path/to/tmux-remote-linux/SKILL.md "$HOME/.codex/skills/tmux-remote-linux/"
cp -R /path/to/tmux-remote-linux/scripts "$HOME/.codex/skills/tmux-remote-linux/"
chmod +x "$HOME/.codex/skills/tmux-remote-linux/scripts/"*.sh
```

Codex 启动时会自动加载 `~/.codex/skills/` 下的 skill，无需额外配置。

如果希望 agent 在合适的时机自动使用这个 skill，可以在项目的 `AGENTS.md`、`CLAUDE.md`、`GEMINI.md` 或常用提示词里加入类似规则：

```text
如果你准备使用 ssh，请改用 tmux-remote-linux。即使普通 SSH 可以连接，也应由用户先准备好 tmux pane，再让 agent 操作该 pane。除非用户明确要求直接 SSH，否则不要自行新开 SSH 连接。
```

这条规则适合放在具体业务项目里，因为它告诉 agent：`ssh` 是触发信号。只要任务需要远程 shell，就应该优先走用户已经准备好的 tmux pane，而不是先尝试直接 SSH。

### Claude Code

在 `~/.claude/commands/` 下创建一个 `.md` 文件，内容指向 `SKILL.md`：

```bash
mkdir -p "$HOME/.claude/commands"
cat > "$HOME/.claude/commands/tmux-remote.md" << 'EOF'
Read and follow ~/.codex/skills/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
EOF
```

如果你已经为 Codex 安装了脚本（见上一节），直接用上面这行就行。如果没装 Codex，把路径改成你的克隆目录即可，例如：

```bash
cat > "$HOME/.claude/commands/tmux-remote.md" << 'EOF'
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
EOF
```

使用时在 Claude Code 中输入 `/tmux-remote` 触发。

### Gemini CLI

在 `~/.gemini/commands/` 下创建一个 `.toml` 文件：

```bash
mkdir -p "$HOME/.gemini/commands"
cat > "$HOME/.gemini/commands/tmux-remote.toml" << 'EOF'
description = "Read and write a remote Linux terminal through tmux"

prompt = """
Read and follow /path/to/tmux-remote-linux/SKILL.md, then execute the bundled scripts there.
"""
EOF
```

使用时在 Gemini CLI 中输入 `/tmux-remote` 触发。

### 其他工具

核心逻辑全在 `SKILL.md` 和 `scripts/` 里。只要你的 AI 工具支持自定义命令/技能，写一句"读取并遵循 SKILL.md 的指示"即可，脚本无需任何修改。

## tmux 准备

创建或进入一个名为 `remote` 的本地 tmux session：

```bash
tmux new -s remote
```

常用 tmux 命令：

```bash
tmux ls                         # 查看已有 session
tmux new -s remote              # 创建并进入 remote session
tmux new -d -s remote           # 后台创建 remote session
tmux attach -t remote           # 重新进入 remote session
tmux switch -t remote           # 在 tmux 内切换到 remote session
tmux list-panes -a              # 查看所有 pane 和 target
tmux kill-session -t remote     # 关闭 remote session
tmux kill-server                # 关闭当前用户的整个 tmux server
```

`tmux kill-server` 会关闭当前用户的所有 tmux session，通常只在确认没有其他重要会话时使用。

在这个 tmux pane 里，由用户自己登录远端机器：

```bash
ssh your-bastion-or-host
ssh your-target-host
```

脚本默认操作 `remote:0.0`。

如果你的 pane 不是这个 target，可以覆盖：

```bash
export REMOTE_TMUX_TARGET=remote:0.1
```

## 必须选择环境

使用任何脚本前，必须明确声明目标环境是生产还是非生产：

```bash
export REMOTE_TMUX_ENV=production
# 或
export REMOTE_TMUX_ENV=non-production
```

这是强制要求。如果 `REMOTE_TMUX_ENV` 未设置或值不合法，所有脚本都会拒绝继续执行。

### 生产环境模式

生产环境下，任何通过 `send.sh` 或 `run.sh` 发送的命令都会停下来要求本地人工确认。

默认是不执行。普通 CLI 使用时，脚本会显示一个随机的 0-9 数字。只有用户输入这个数字后，命令才会发送到 tmux pane。

如果是 Codex 或其他聊天式 agent 使用，agent 应该先在聊天里展示：目标 pane、完整命令、这条命令要做什么的中文解释，以及一个新的随机数字。审批提示应该尽量紧凑，带 `目标` 和 `说明` 标签的信息放在一行，命令单独放在下一行，批准数字放在同一行末尾。字段用 Markdown 粗体和行内代码高亮。不要使用 HTML 标签或内联 CSS，因为某些终端渲染器会把它们原样显示出来。用户只需要回复这个数字，即表示同意执行这一条命令。随后 agent 可以把这个数字和解释作为本次命令的一次性批准参数传给脚本。

普通 CLI 交互确认前会显示带 `!!!` 的醒目警告。聊天式 agent 已经在聊天里展示生产审批时，脚本不会重复输出这些警告。只要这个 pane 可能影响真实用户、真实数据、线上基础设施、账单、安全状态或其他生产系统，就应该使用生产环境模式。

### 非生产环境模式

非生产环境下，`send.sh` 和 `run.sh` 不做生产确认。这个模式只应该用于测试、开发、预发、临时环境或其他可接受风险的目标。

## 使用方法

读取最近 40 行 pane 输出：

```bash
scripts/read.sh
```

读取指定行数：

```bash
scripts/read.sh 80
```

发送一条改变 shell 状态或长时间运行的 shell 命令：

```bash
scripts/send.sh 'cd /var/log'
```

执行一条短检查命令，并只返回这条命令的输出：

```bash
scripts/run.sh 'pwd; hostname; date'
```

示例输出：

```text
/root
remote-host
Thu Apr 30 10:30:00 UTC 2026

[exit 0]
```

如果远端命令返回非零退出码，`run.sh` 会打印 `[exit N]`，并且本地脚本也会用同样的退出码退出。

## 整体工作流程

这个 skill 的核心模型是：用户先准备好一个本地 tmux pane，并在里面完成远端登录、MFA、SSH 跳转、切换用户、选择 kubeconfig 等初始化；agent 只通过 `read.sh`、`send.sh` 和 `run.sh` 读写这个 pane。脚本不管理 SSH 连接、不保存凭据、不知道服务器资产清单，也不会创建独立的远端会话。

一次典型操作通常是：

1. agent 先用 `read.sh` 查看当前 pane。
2. 根据 prompt 和输出判断当前主机、用户、目录、是否在 REPL、是否有前台命令正在运行。
3. 根据命令类型选择 `run.sh` 或 `send.sh`。
4. 如果目标是生产环境，`send.sh` / `run.sh` 在发送命令前要求人工确认。
5. 命令执行后，agent 读取或截取输出，向用户汇总关键结果。
6. 如果遇到密码、MFA、token 等敏感提示，agent 停止发送输入，由用户直接在 tmux pane 里完成，然后 agent 再读取当前状态继续。

### `read.sh`

`read.sh` 只读取 tmux pane 最近若干行输出，不向远端发送任何输入。它会先检查 `REMOTE_TMUX_ENV`，然后读取 `REMOTE_TMUX_TARGET` 指向的 pane。默认会过滤明显的 Codex wrapper 和 marker 行，避免把传输层细节混进正常上下文。

`read.sh` 适合用来确认当前 prompt、主机、目录、前台程序状态，或者在长命令运行时少量轮询进度。

### `send.sh`

`send.sh` 会向 tmux pane 发送一条 shell 命令，并按一次回车。默认情况下，它会在命令前加 shell history 清理包装，因此只适用于普通 shell prompt。它不截取输出，也不知道远端退出码。

`send.sh` 适合会改变当前交互 shell 状态的命令，例如 `cd`、`export`、`sudo -i`；也适合长时间运行的 shell 命令、需要用户手动输入密码后的后续操作。因为它直接作用于当前 pane，发送前必须确认当前 prompt 和上下文。

默认情况下，`send.sh` 会写一条本地 JSONL 审计事件，包含 request id、解码后的命令、目标 pane、环境和发送时间。因为 `send.sh` 不等待命令结束，所以事件里的 `exit_code` 和 `output` 都是 `null`。

`send.sh` 不支持 MySQL、Redis、Spark shell、psql、Python、Node 等 REPL 式交互命令行，也不支持 Oasis `work>` 这类内部工具 prompt。它会检测常见的非 shell prompt 并拒绝发送，避免把 shell-only 包装灌进交互式 CLI。对这类工具，优先使用一次性非交互命令，例如 `mysql -e`、`redis-cli <command>`、`spark-sql -e`、`python -c`、`node -e`。如果 pane 已经进入 REPL 或工具 prompt，agent 应报告当前状态，并使用拥有该 CLI 的专用 skill；即使是 `exit`、`quit`、`bye`、`\q` 这类退出命令，也应由专用 skill 以原始 CLI 语法发送。

### `run.sh`

`run.sh` 适合短小、非交互式检查命令。它会先检查配置和当前 pane 状态，拒绝在明显的 MySQL、psql、Python、Spark 等交互式 prompt 上包裹命令；如果发现上一次 `run.sh` 的 begin marker 还没有对应的 end marker，也会拒绝继续发送新命令，避免命令叠加污染 pane。

通过检查后，`run.sh` 会生成唯一 begin/end marker，在本地把用户命令 base64 编码，然后向 tmux pane 发送一个 wrapper。这个 wrapper 在远端打印 begin marker，执行：

```bash
base64 -d | bash
```

随后记录远端命令的退出码，打印 end marker 和退出码。`run.sh` 再从 tmux pane 最近输出中找到 begin/end marker，只返回这次命令的输出，并打印 `[exit N]`。本地脚本也会用同样的退出码结束。

命令通过 base64 传输，是为了减少嵌套引号、管道、分号、多层 shell 转义带来的问题。命令在远端子 `bash` 中执行，因此 `exit 7` 只会结束子进程，不会关闭当前交互 shell；但也意味着 `cd`、`export` 这类状态变化不会保留到命令结束之后。

默认情况下，`run.sh` 会写一条本地 JSONL 审计事件，包含 request id、解码后的命令、目标 pane、环境、开始时间、结束时间、耗时、退出码和截断后的命令输出。`run.sh` 和 `send.sh` 也会在本地打印 `[request_id ...]`，方便以后把终端输出对应回 JSONL。

### 远端 history 减噪

默认情况下，发送到 tmux 的命令会带上 shell history 设置和前导空格。对 bash，wrapper 会设置 `HISTCONTROL=ignoreboth:erasedups`；对 zsh，会尝试执行 `setopt HIST_IGNORE_SPACE`。发送的命令执行完成后，wrapper 还会尽量从交互 shell history 中删除刚刚发送的这一条记录。`run.sh` 还会把传输 wrapper 放到 `HISTFILE=/dev/null` 的子 `bash` 里执行。

这个机制的目标是减少普通交互 shell history 里的噪音，尤其是 AI 生成的超长 base64 wrapper 和试错命令。它不是安全边界，也不尝试绕过终端录屏、堡垒机审计、系统 audit 日志或云厂商会话日志。

### 状态边界

tmux pane 是共享的可变状态，不是隔离沙箱。`send.sh` 会改变当前交互 shell；`run.sh` 会在当前目录和环境的基础上启动一个子 `bash`；用户手动输入、前台程序、REPL、SSH 跳转、容器 shell 和 kubeconfig 都会影响后续命令含义。`vim`、`nano`、`less`、`top`、`htop`、`watch` 这类全屏 TUI 程序不是线性文本协议，agent 很难可靠判断模式、光标、滚屏、保存状态和退出行为，应尽量避免由 agent 操作。

因此，agent 在继续操作前应确认当前 pane 状态；未知大小的输出应有限读取；敏感输入应由用户手动完成；生产环境命令应逐条确认。这个项目提供的是一个很窄的终端传输通道，不是权限系统，也不是远端状态管理器。

## 配置项

```bash
REMOTE_TMUX_TARGET=remote:0.0
REMOTE_TMUX_ENV=non-production
REMOTE_TMUX_LINES=40
REMOTE_TMUX_FILTER_WRAPPER=1
REMOTE_TMUX_RUN_WAIT_SECONDS=1
REMOTE_TMUX_RUN_CAPTURE_LINES=400
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40
REMOTE_TMUX_DETECT_INTERACTIVE=1
REMOTE_TMUX_AVOID_REMOTE_HISTORY=1
REMOTE_TMUX_LOG_ENABLED=1
REMOTE_TMUX_LOG_DIR="$HOME/.codex/tmux-remote-linux/logs"
REMOTE_TMUX_LOG_MAX_OUTPUT_LINES=10
REMOTE_TMUX_LOG_RETENTION_DAYS=7
REMOTE_TMUX_REQUEST_ID=<可选的固定ID>
REMOTE_TMUX_COMMAND_EXPLANATION='解释这条生产命令要做什么'
REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT=7
REMOTE_TMUX_PROD_APPROVAL_DIGIT=7
```

### `REMOTE_TMUX_TARGET`

要操作的 tmux pane，默认是 `remote:0.0`。

### `REMOTE_TMUX_ENV`

必填。只能是：

- `production`
- `non-production`

### `REMOTE_TMUX_LINES`

`read.sh` 默认读取的行数，默认 `40`。

### `REMOTE_TMUX_FILTER_WRAPPER`

`read.sh` 是否过滤明显的 Codex wrapper 和 marker 行，默认 `1`。过滤规则很保守：隐藏 `__CODEX_RUN_...` marker；隐藏 wrapper 命令行时要求同一行同时包含 `__CODEX_RUN_...`、`base64 -d | bash` 和 `__codex_status`，避免误伤普通 base64 输出。排查传输层问题时可以设置为 `0`。

### `REMOTE_TMUX_RUN_WAIT_SECONDS`

`run.sh` 发送命令后等待多久再抓取输出，默认 `1` 秒。

### `REMOTE_TMUX_RUN_CAPTURE_LINES`

`run.sh` 为了寻找 begin/end marker 抓取多少行 pane 输出，默认 `400`。

### `REMOTE_TMUX_RUN_MAX_OUTPUT_LINES`

`run.sh` 最多打印多少行本次命令输出，默认 `200`。

### `REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES`

`run.sh` 最多打印多少字节本次命令输出，默认 `32768`。

### `REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES`

如果 `run.sh` 找到了 begin marker，但还没找到 end marker，只打印 begin marker 后最近多少行输出，默认 `40`。

### `REMOTE_TMUX_DETECT_INTERACTIVE`

设置为 `1` 时，如果 pane 看起来已经在 MySQL、psql、Python、Spark shell、redis-cli、mongo shell、sqlite 等子交互 CLI 里，`run.sh` 会拒绝执行。默认 `1`。

### `REMOTE_TMUX_AVOID_REMOTE_HISTORY`

设置为 `1` 时，`send.sh` 和 `run.sh` 会在发送命令前加 history 忽略设置和前导空格，并在命令结束后尽量从交互 shell history 中删除刚刚发送的这一条记录，减少远端交互 shell history 污染。默认 `1`。

### `REMOTE_TMUX_LOG_ENABLED`

`send.sh` 和 `run.sh` 是否写本地 JSONL 审计日志。默认 `1`。设置为 `0` 可关闭。

### `REMOTE_TMUX_LOG_DIR`

本地审计日志目录。默认 `$HOME/.codex/tmux-remote-linux/logs`。日志按本地日期分文件，例如 `2026-05-17.jsonl`。

### `REMOTE_TMUX_LOG_MAX_OUTPUT_LINES`

每条 `run.sh` 审计事件最多保存多少行命令输出。默认 `10`。它不影响 `run.sh` 打印给调用方的行数；打印行数由 `REMOTE_TMUX_RUN_MAX_OUTPUT_LINES` 控制。

### `REMOTE_TMUX_LOG_RETENTION_DAYS`

本地 `*.jsonl` 审计日志保留多少天。默认 `7`。清理会在写入新日志事件时顺手执行。

### `REMOTE_TMUX_REQUEST_ID`

单次 `run.sh` 或 `send.sh` 可选指定的 request id。如果不设置，脚本会用本地时间和进程 id 自动生成。这个 id 会由脚本打印出来，并写入 JSONL，方便把终端输出、聊天上下文和本地日志对应起来。

### `REMOTE_TMUX_COMMAND_EXPLANATION`

非生产环境可选。非交互式生产环境批准时必填。这里应该用用户容易理解的语言解释命令要做什么、为什么需要执行。

### `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT`

聊天式 agent 的生产环境批准参数。表示执行前展示给用户的一位随机数字。

### `REMOTE_TMUX_PROD_APPROVAL_DIGIT`

聊天式 agent 的生产环境批准参数。表示用户回复的数字。只有它和 `REMOTE_TMUX_PROD_APPROVAL_EXPECTED_DIGIT` 一致，并且提供了 `REMOTE_TMUX_COMMAND_EXPLANATION`，脚本才接受非交互式生产环境执行。

## token 消耗

通过 tmux 操作远端终端时，token 消耗通常会比直接在本地仓库里工作稍大一些。原因是 agent 需要反复读取终端上下文、确认当前 prompt、过滤 wrapper 输出，并把远端命令结果摘要给用户。远端命令如果输出很多日志、表格或历史 pane 内容，也会直接增加上下文和回复消耗。

降低 token 消耗的建议：

- 优先用 `run.sh` 执行短小、明确的检查命令，让脚本只返回本次命令的输出。
- 避免让远端命令直接打印大量日志；先用 `tail -n`、`head -n`、`grep`、`awk`、`sed`、`jq` 等工具缩小结果。
- 读取 pane 时按需指定较小行数，例如 `scripts/read.sh 20`，不要习惯性读取几百行。
- 对 `kubectl get`、日志查询、数据库查询等命令，优先加 namespace、label、时间范围、字段选择或 limit。
- 长任务运行中优先等待并少量轮询，不要频繁抓取大段输出。

可以调节 token 消耗的配置项：

```bash
REMOTE_TMUX_LINES=40                    # read.sh 默认读取行数
REMOTE_TMUX_RUN_CAPTURE_LINES=400       # run.sh 为寻找 marker 抓取的 pane 行数
REMOTE_TMUX_RUN_MAX_OUTPUT_LINES=200    # run.sh 最多打印本次命令多少行输出
REMOTE_TMUX_RUN_MAX_OUTPUT_BYTES=32768  # run.sh 最多打印本次命令多少字节输出
REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES=40 # 长命令未结束时最多打印多少行尾部输出
REMOTE_TMUX_FILTER_WRAPPER=1            # 过滤明显的 wrapper 和 marker 行
REMOTE_TMUX_LOG_MAX_OUTPUT_LINES=10     # 本地审计日志最多保存多少行输出
```

如果只是日常巡检，可以把 `REMOTE_TMUX_LINES`、`REMOTE_TMUX_RUN_MAX_OUTPUT_LINES` 和 `REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES` 调小。排查复杂问题时再临时调大，避免把大量无关历史输出带进 agent 上下文。

## 什么时候用 `send.sh`，什么时候用 `run.sh`

短小、非交互式检查命令适合用 `run.sh`：

```bash
scripts/run.sh 'systemctl status nginx --no-pager'
scripts/run.sh 'kubectl get pods -n default'
scripts/run.sh 'df -h'
```

会改变 shell 状态或会持续运行的 shell 命令适合用 `send.sh`：

```bash
scripts/send.sh 'cd /opt/app'
scripts/send.sh 'sudo -i'
scripts/send.sh 'tail -f /var/log/app.log'
```

`run.sh` 会在远端子 `bash` 进程里执行命令。因此 `cd`、`export` 这类 shell 状态变化不会在命令结束后保留。需要保留状态时，请用 `send.sh`。

作为软性的审计策略：需要记录命令结果时优先用 `run.sh`；切目录、设置环境、启动长任务或把控制权交还用户时优先用 `send.sh`。这是建议，不是硬性限制。

不支持由这个 skill 操作 REPL 式交互命令行。典型例子包括 `mysql>`、`redis-cli`、`psql>`、`spark-shell>`、Python REPL、Node REPL、已经 attach 进去的容器 shell、Oasis `work>` 这类内部工具 prompt，或者任何状态存在于当前交互程序内部的 prompt。请改用非交互命令，例如 `mysql -e`、`redis-cli <command>`、`spark-sql -e`、`python -c`、`node -e`；如果某个项目确实需要对其中一种 CLI 做有限自动化，应创建该 CLI 的专用 skill。专用 skill 要知道如何进入 prompt、只执行受支持命令，并用正确的原始语法退出。

复杂的多步骤检查，尤其是跨多台机器、包含循环、正则、管道和多层 `ssh` 的检查，不适合硬拼成很长的一行 shell。多层引号会同时经过本地 shell、`run.sh`、远端 shell、子 `bash` 和内层 `ssh`，很容易出现语法错误。

在非生产环境中，更稳的做法是写一个临时脚本到 `/tmp`，用普通多行 shell 表达逻辑，限制输出，执行后清理。例如：

```bash
tmp="/tmp/tmux-remote-linux-check-$$.sh"
cat > "$tmp" <<'EOF'
#!/usr/bin/env bash
set -u
for h in master1 master2 master3; do
  echo "===== $h ====="
  ssh "$h" hostname
  ssh "$h" "ss -lntp | grep 9092 | head -n 5"
done
EOF
bash "$tmp"
rm -f "$tmp"
```

生产环境中不要默认写临时脚本。只有用户明确批准，且脚本内容、路径、影响范围都清楚时，才考虑这么做。

## `run.sh` 工作原理

`run.sh` 会：

1. 生成唯一 begin/end marker。
2. 在本地把命令 base64 编码。
3. 把一个小 wrapper 发送进 tmux pane。
4. 在远端解码命令并用 `bash` 执行。
5. 抓取最近 pane 输出。
6. 只打印 begin/end marker 之间的内容，并受行数和字节数限制。
7. 打印 `[exit N]`，并用同样的退出码结束本地脚本。

这样可以避免大部分嵌套引号问题，也能避免 `exit 7` 这类命令关闭当前远端 shell。

如果找不到 begin marker，`run.sh` 不会打印旧 pane 历史。如果找到了 begin marker 但还没找到 end marker，它只会打印本次命令的一小段尾部输出，并返回 `124`。

## 注意事项

- **稳妥优先，不追求全面交互能力。** 这个 skill 适合普通 shell 命令、短检查、有限输出、长任务启动和状态确认；不适合让 agent 像人一样操作复杂交互式命令行。
- **托管 pane 不应以交互式命令行状态交给这个 skill。** 把 pane 交给这个 skill 前，应退出 MySQL、Redis、psql、Spark shell、Python REPL、Node REPL、容器内交互 shell、`vim`、`less`、`top`、`watch` 等状态，回到清晰的普通 shell prompt。如果另一个 skill 拥有该 CLI，应由那个 skill 负责退出；不要用 `tmux-remote-linux/send.sh` 退出非 shell CLI。
- **把 agent 正在使用的 tmux pane 视为 agent 托管终端。** 用户尽量不要同时在这个 pane 里手动输入命令。手动操作会改变 cwd、用户、主机、环境变量、kubeconfig、REPL 状态和输出边界，可能导致 agent 误判上下文或把输出归属到错误命令。
- **最佳实践是让托管 tmux session 默认不可见。** 远端 shell 准备好后，建议用 `Ctrl-b d` detach 这个 tmux session，让 agent 在后台操作。用户只有在需要输入密码、MFA、token，或明确要接管时才 `tmux attach -t remote` 回来；操作完成后应再次 detach。不要把 agent 托管 pane 长时间留在普通终端窗口里，避免顺手拿来做其他生产或测试操作。
- `REMOTE_TMUX_ENV` 只控制脚本的确认策略，不会检测当前远端到底是测试环境还是生产环境。如果用户手动把托管 pane 从测试机切到生产机，agent 可能仍按旧假设继续发送命令。因此，托管 pane 不应作为日常手工运维终端使用。
- 如果需要手动操作，建议使用另一个终端、另一个 tmux pane 或另一个 tmux session；如果希望 agent 后续理解和接手，最好直接让 agent 代为执行。
- 如果已经手动改动了托管 pane，应先告诉 agent 执行了什么、当前在哪台机器、哪个用户、哪个目录、是否进入了容器或 REPL，再让它继续。
- **敏感输入由用户手动完成。** 不要把 SSH 密码、数据库密码、`sudo` 密码、MFA code、API token、私钥内容或其他凭据贴给 agent。
- 若命令进入密码、MFA 或其他敏感提示，agent 应停止继续发送输入，并让用户直接在 tmux pane 中输入。用户完成后只需告诉 agent“已经输入完成”“已经登录成功”或“可以继续”。agent 随后应重新读取 pane，确认当前 prompt、主机、用户、目录和上下文，再继续操作。
- 避免让 agent 操作 `vim`、`nano`、`less`、`top`、`htop`、`watch` 等全屏 TUI。查看文件优先使用 `sed -n`、`head`、`tail`、`grep`；搜索优先使用 `grep`、`rg`、`find`；需要编辑复杂文件时，建议用户手动编辑，完成后告诉 agent 继续检查。
- 把 tmux pane 当成共享的可变状态。
- 执行任何操作前，先确认当前 prompt、主机、用户、目录、kubeconfig 和 shell 上下文。
- 小心陈旧 pane。pane 里显示的主机可能已经不是你以为的那个。
- 小心 alias、shell function、环境变量和虚拟环境。
- 生产环境下，不理解命令和影响范围时，不要输入或回复批准数字。
- 生产环境每条命令都应该单独确认。不要只根据命令开头判断风险；shell 上下文、kubeconfig、alias、环境变量和业务逻辑都可能改变真实影响。
- 改变 shell 状态或长时间运行的 shell 命令用 `send.sh`，有边界的检查命令用 `run.sh`；REPL 式交互命令行不由这个 skill 操作。
- 避免通过这个工具执行多行生产操作。复杂流程应由用户自己在终端里操作。
- 不要把这个项目当成权限系统。它只是本地安全保护，不是安全边界。

高风险命令需要额外谨慎，包括但不限于：

- `rm`、`mv`、`chmod -R`、`chown -R`
- `dd`、`mkfs`、分区、挂载变更
- `systemctl restart`、`systemctl stop`
- `kubectl delete`、`kubectl apply`、`kubectl scale`
- `helm upgrade`、`helm uninstall`
- `terraform apply`、`terraform destroy`
- 防火墙、路由、重启、关机、数据库迁移、数据删除类命令

## 审计日志

`send.sh` 和 `run.sh` 默认会写本地 append-only JSONL 审计日志。默认目录是：

```bash
$HOME/.codex/tmux-remote-linux/logs
```

文件按本地日期拆分：

```text
2026-05-17.jsonl
```

`run.sh` 会记录 request id、解码后的命令、目标 pane、环境、开始时间、结束时间、耗时、退出码，以及按 `REMOTE_TMUX_LOG_MAX_OUTPUT_LINES` 截断后的输出。`send.sh` 会记录 request id、解码后的命令、目标 pane、环境和发送时间，但因为它不等待命令完成，所以 `exit_code: null`、`output: null`。

可以用 `scripts/logs.sh` 查询日志：

```bash
scripts/logs.sh path
scripts/logs.sh last 10
scripts/logs.sh today 20
scripts/logs.sh failures
scripts/logs.sh grep df
scripts/logs.sh show 20260517-172200-12345
scripts/logs.sh output 20260517-172200-12345
```

`logs.sh` 需要本机安装 `jq`。

审计日志是本地敏感文件，里面可能包含生产命令、主机名、业务输出或错误细节。用户直接在 pane 里手动输入的密码、MFA code 和密钥不会被这些脚本捕获，但命令文本和命令输出本身仍可能包含敏感信息。

超过 `REMOTE_TMUX_LOG_RETENTION_DAYS` 天的旧 `*.jsonl` 文件会被删除。清理是机会式的：写入新日志事件时顺手执行。

## 常见问题

### `REMOTE_TMUX_ENV is required`

明确设置环境：

```bash
export REMOTE_TMUX_ENV=non-production
```

或者：

```bash
export REMOTE_TMUX_ENV=production
```

### `error connecting to ... tmux`

确认 tmux 正在运行，并且目标 pane 存在：

```bash
tmux list-sessions
tmux list-panes -a
```

必要时设置 `REMOTE_TMUX_TARGET`。

### `begin marker not found yet`

`run.sh` 没有在抓取的 pane 输出里看到自己这次 wrapper 的开始 marker。它会刻意避免打印旧 pane 历史。可以直接查看当前 pane：

```bash
scripts/read.sh 40
```

### `end marker not found yet`

命令可能还在运行，或者抓取窗口太小。可以增大：

```bash
export REMOTE_TMUX_RUN_CAPTURE_LINES=1000
```

然后查看 pane：

```bash
scripts/read.sh 200
```

### `interactive prompt detected`

当前 pane 看起来已经在 MySQL、psql、Python、Spark shell、redis-cli、mongo shell、sqlite 等子交互 CLI 里，或者在 Oasis `work>` 这类内部工具 prompt 中。agent 不应通过这个 skill 继续发送 REPL 输入。请用户退出或手动处理该 REPL，使用该 CLI 的专用 skill，或者改用 `mysql -e`、`redis-cli <command>`、`spark-sql -e`、`python -c`、`node -e` 这类非交互命令。

### `run.sh` 里的 `cd` 或 `export` 没有保留

这是预期行为。需要改变远端 shell 状态时，用 `send.sh`：

```bash
scripts/send.sh 'cd /opt/app'
```

## 免责声明

使用本项目的风险由你自行承担。远程终端自动化可能导致服务中断、数据丢失、安全事故、不可逆的运维损坏、经济损失或业务中断，尤其是在生产环境中。

你需要自行负责审查命令、理解影响、确认目标环境，并决定是否执行。项目作者和贡献者不对因使用或误用本工具导致的任何损害、损失、停机、应急响应成本、业务影响、安全事故、数据丢失或第三方索赔承担责任。
