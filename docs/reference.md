# tmux-remote-linux reference

This is the full reference manual. For the short setup path, start with [../README.md](../README.md).

`tmux-remote-linux` 是一个用于 AI 编程工具的小型 skill。它通过用户本地已经打开的 tmux pane 操作远程 Linux shell。

这个工具适合这样的场景：用户已经手动完成了堡垒机登录、MFA、SSH 跳转、内网访问、切换 root、选择 kubeconfig 等准备工作。Codex 不需要拿到凭据，也不需要自己重新建立 SSH 连接，只通过 tmux pane 读取输出、发送命令、汇总结果。

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
- `SKILL.md`：给 AI 工具使用的安全操作说明。

## 依赖

本机需要：

- macOS、Linux，或 Windows 上的 WSL 环境
- `bash`
- `tmux`
- `base64`
- `awk`、`grep`、`sed`

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

如果是 Codex 或其他聊天式 agent 使用，agent 应该先在聊天里展示：目标环境、完整命令、这条命令要做什么的中文解释，以及一个新的随机数字。审批提示应该尽量紧凑，目标和环境放在一行，命令从下一行开始，批准数字直接放在批准句末尾。字段用 Markdown 粗体和行内代码高亮。不要使用 HTML 标签或内联 CSS，因为某些终端渲染器会把它们原样显示出来。用户只需要回复这个数字，即表示同意执行这一条命令。随后 agent 可以把这个数字和解释作为本次命令的一次性批准参数传给脚本。

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

发送一条交互式或改变 shell 状态的命令：

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

`send.sh` 会把命令按字面发送到 tmux pane，并按一次回车。它不包裹命令、不截取输出，也不知道远端退出码。

`send.sh` 适合会改变当前交互 shell 状态的命令，例如 `cd`、`export`、`sudo -i`；也适合 REPL 输入、长时间运行的命令、需要用户手动输入密码后的后续操作。因为它直接作用于当前 pane，发送前必须确认当前 prompt 和上下文。

### `run.sh`

`run.sh` 适合短小、非交互式检查命令。它会先检查配置和当前 pane 状态，拒绝在明显的 MySQL、psql、Python、Spark 等交互式 prompt 上包裹命令；如果发现上一次 `run.sh` 的 begin marker 还没有对应的 end marker，也会拒绝继续发送新命令，避免命令叠加污染 pane。

通过检查后，`run.sh` 会生成唯一 begin/end marker，在本地把用户命令 base64 编码，然后向 tmux pane 发送一个 wrapper。这个 wrapper 在远端打印 begin marker，执行：

```bash
base64 -d | bash
```

随后记录远端命令的退出码，打印 end marker 和退出码。`run.sh` 再从 tmux pane 最近输出中找到 begin/end marker，只返回这次命令的输出，并打印 `[exit N]`。本地脚本也会用同样的退出码结束。

命令通过 base64 传输，是为了减少嵌套引号、管道、分号、多层 shell 转义带来的问题。命令在远端子 `bash` 中执行，因此 `exit 7` 只会结束子进程，不会关闭当前交互 shell；但也意味着 `cd`、`export` 这类状态变化不会保留到命令结束之后。

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
```

如果只是日常巡检，可以把 `REMOTE_TMUX_LINES`、`REMOTE_TMUX_RUN_MAX_OUTPUT_LINES` 和 `REMOTE_TMUX_RUN_PENDING_OUTPUT_LINES` 调小。排查复杂问题时再临时调大，避免把大量无关历史输出带进 agent 上下文。

## 什么时候用 `send.sh`，什么时候用 `run.sh`

短小、非交互式检查命令适合用 `run.sh`：

```bash
scripts/run.sh 'systemctl status nginx --no-pager'
scripts/run.sh 'kubectl get pods -n default'
scripts/run.sh 'df -h'
```

会改变 shell 状态、需要交互、或会持续运行的命令适合用 `send.sh`：

```bash
scripts/send.sh 'cd /opt/app'
scripts/send.sh 'sudo -i'
scripts/send.sh 'tail -f /var/log/app.log'
```

`run.sh` 会在远端子 `bash` 进程里执行命令。因此 `cd`、`export` 这类 shell 状态变化不会在命令结束后保留。需要保留状态时，请用 `send.sh`。

如果 pane 已经进入了子交互 CLI，请使用 `send.sh`，不要使用 `run.sh`。典型例子包括 `mysql>`、`psql>`、`spark-shell>`、Python REPL、已经 attach 进去的容器 shell，或者任何状态存在于当前交互程序内部的 prompt。`send.sh` 会按字面发送文本再按回车，更适合 SQL 语句、Python 表达式、Spark shell 命令这类 REPL 输入。

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

- **把 agent 正在使用的 tmux pane 视为 agent 托管终端。**用户尽量不要同时在这个 pane 里手动输入命令。手动操作会改变 cwd、用户、主机、环境变量、kubeconfig、REPL 状态和输出边界，可能导致 agent 误判上下文或把输出归属到错误命令。
- **最佳实践是让托管 tmux session 默认不可见。**远端 shell 准备好后，建议用 `Ctrl-b d` detach 这个 tmux session，让 agent 在后台操作。用户只有在需要输入密码、MFA、token，或明确要接管时才 `tmux attach -t remote` 回来；操作完成后应再次 detach。不要把 agent 托管 pane 长时间留在普通终端窗口里，避免顺手拿来做其他生产或测试操作。
- `REMOTE_TMUX_ENV` 只控制脚本的确认策略，不会检测当前远端到底是测试环境还是生产环境。如果用户手动把托管 pane 从测试机切到生产机，agent 可能仍按旧假设继续发送命令。因此，托管 pane 不应作为日常手工运维终端使用。
- 如果需要手动操作，建议使用另一个终端、另一个 tmux pane 或另一个 tmux session；如果希望 agent 后续理解和接手，最好直接让 agent 代为执行。
- 如果已经手动改动了托管 pane，应先告诉 agent 执行了什么、当前在哪台机器、哪个用户、哪个目录、是否进入了容器或 REPL，再让它继续。
- **敏感输入由用户手动完成。**不要把 SSH 密码、数据库密码、`sudo` 密码、MFA code、API token、私钥内容或其他凭据贴给 agent。
- 若命令进入密码、MFA 或其他敏感提示，agent 应停止继续发送输入，并让用户直接在 tmux pane 中输入。用户完成后只需告诉 agent“已经输入完成”“已经登录成功”或“可以继续”。agent 随后应重新读取 pane，确认当前 prompt、主机、用户、目录和上下文，再继续操作。
- 避免让 agent 操作 `vim`、`nano`、`less`、`top`、`htop`、`watch` 等全屏 TUI。查看文件优先使用 `sed -n`、`head`、`tail`、`grep`；搜索优先使用 `grep`、`rg`、`find`；需要编辑复杂文件时，建议用户手动编辑，完成后告诉 agent 继续检查。
- 把 tmux pane 当成共享的可变状态。
- 执行任何操作前，先确认当前 prompt、主机、用户、目录、kubeconfig 和 shell 上下文。
- 小心陈旧 pane。pane 里显示的主机可能已经不是你以为的那个。
- 小心 alias、shell function、环境变量和虚拟环境。
- 生产环境下，不理解命令和影响范围时，不要输入或回复批准数字。
- 生产环境每条命令都应该单独确认。不要只根据命令开头判断风险；shell 上下文、kubeconfig、alias、环境变量和业务逻辑都可能改变真实影响。
- 交互式命令用 `send.sh`，有边界的检查命令用 `run.sh`。
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

## 未来：审计日志

审计日志是一个有价值但尚未实现的方向。这个项目当前依赖 tmux scrollback、agent 对话记录和用户自己的操作记录；如果 agent 退出、tmux session 关闭或 scrollback 被覆盖，事后复盘会不够稳定。

未来可以考虑增加本地 append-only 审计日志，用于记录 agent 通过 `send.sh` / `run.sh` 发送过的命令、目标 pane、环境、时间、生产批准说明、退出码和 `run.sh` 捕获到的输出摘要。日志格式可以优先考虑 JSONL，方便以后写查询、过滤、摘要和风险分析工具。

需要明确的是，审计日志的核心价值不只是“记录下来”，而是“以后怎么查”。在查询工具和使用方式没有想清楚之前，不宜过早把日志格式和字段固定下来。

设计时还需要处理这些边界：

- `run.sh` 可以记录命令输出和退出码，`send.sh` 通常只能记录发送了什么，未必知道后续输出和退出码。
- 用户手动输入的密码、MFA、token 或其他敏感内容不应被 agent 记录。
- 审计日志本身可能包含敏感命令、生产输出、业务数据或连接信息，应作为本地敏感文件处理，并使用严格权限。
- 大输出不应完整写入主日志；可以只记录摘要、截断内容，或把详细输出拆到单独文件。
- 多 agent、多 pane、多 session 并发写日志时，需要有 request id / run id / target 等字段帮助归因。

这个功能适合等查询需求更清楚后再实现。当前文档只记录设计方向，不表示现有脚本已经提供审计日志能力。

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

当前 pane 看起来已经在 MySQL、psql、Python、Spark shell、redis-cli、mongo shell、sqlite 等子交互 CLI 里。请使用 `send.sh` 发送一条 REPL 输入，再用 `read.sh` 查看结果。

### `run.sh` 里的 `cd` 或 `export` 没有保留

这是预期行为。需要改变远端 shell 状态时，用 `send.sh`：

```bash
scripts/send.sh 'cd /opt/app'
```

## 免责声明

使用本项目的风险由你自行承担。远程终端自动化可能导致服务中断、数据丢失、安全事故、不可逆的运维损坏、经济损失或业务中断，尤其是在生产环境中。

你需要自行负责审查命令、理解影响、确认目标环境，并决定是否执行。项目作者和贡献者不对因使用或误用本工具导致的任何损害、损失、停机、应急响应成本、业务影响、安全事故、数据丢失或第三方索赔承担责任。
