# tmux-remote-linux

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

- macOS 或 Linux shell 环境
- `bash`
- `tmux`
- `base64`
- `awk`、`grep`、`sed`

远端 pane 里需要：

- 已经可用的 shell prompt
- `run.sh` 需要远端有 `bash`
- 用户已经完成必要的远端初始化，例如登录、切换目录、选择 kubeconfig 等

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
