# tmux-remote-linux 环境设置（macOS）

这是一份面向 macOS 使用者的 `tmux-remote-linux` skill 环境设置指南，以本地 iTerm2 + tmux + AI Agent 为基础，涵盖 skill 本身的环境准备、配置与使用注意事项。内容包括安装、缓冲区、粘贴设置、中文等宽字体、命令别名、Agent 权限，以及 skill 的目标环境和交互边界，方便在一份文档中完成环境准备并了解使用方式。

Linux 用户可以参考其中的 tmux 和 Shell 配置。Windows 用户需要使用 WSL 或 Linux 容器等环境，并让 Agent、tmux 和 skill 运行在同一环境中；本文不展开这些环境的搭建，iTerm2 与 macOS 快捷键部分也不适用。

skill 的安装与不同 AI 工具的接入步骤见[中文参考手册](reference.zh-CN.md#安装)。

本文独立于 `SKILL.md`，不作为 skill 的执行指令，也不改变脚本或业务确认机制。

## 1. 安装本地 tmux

tmux 应安装在 AI Agent 能访问的本机环境中。macOS 使用 Homebrew：

```bash
brew install tmux
tmux -V
```

Linux 按发行版选择安装命令：

```bash
# Debian / Ubuntu
sudo apt-get install tmux

# Fedora / Rocky Linux 等使用 dnf 的系统
sudo dnf install tmux
```

下面的 iTerm2 设置针对 macOS；tmux 配置和别名也适用于 Linux。

## 2. 把缓冲区设大

远程诊断经常连续输出大量日志。历史缓冲区太小，较早的上下文很快就被覆盖。推荐优先保留足够多的历史：**只要可用内存充足，就可以继续调大，不必拘泥于几千行的保守配置。**

这里有两个独立的缓冲区：

| 配置 | 保存什么 | 作用 |
| --- | --- | --- |
| tmux `history-limit` | 每个 pane 的历史输出 | tmux 自己回看、`capture-pane` 读取的来源 |
| iTerm2 Scrollback Buffer | iTerm2 保存的终端显示历史 | 在 iTerm2 中向上滚动查看 |

只扩大 iTerm2 的缓冲区，不会扩大 tmux 的历史。两处都建议设置。

### tmux：建议从 100 万行起步

在本机 `~/.tmux.conf` 中添加或修改对应配置，保留文件中的其他设置：

```tmux
# 允许用鼠标选择 pane 和滚动历史
set -g mouse on

# 每个 pane 最多保留 100 万行历史
set -g history-limit 1000000
```

内存充裕、日志较多时，可以把 `1000000` 改为 `5000000`，甚至更大。这个数值是容量上限，历史随实际输出增长；总占用还取决于 pane 数量、行宽、字符和样式，不能只根据行数换算成固定的内存大小。

已有 tmux server 时，重新加载配置：

```bash
tmux source-file ~/.tmux.conf
tmux show-options -g history-limit
```

**`history-limit` 对新建窗口生效，重新加载不会扩大已有窗口的历史上限，也不能找回已经被覆盖的输出。** 最好在首次创建工作会话前完成配置。安装时可在新建的窗口中查看实际配置与用量：

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} limit=#{history_limit} lines=#{history_size} bytes=#{history_bytes}'
```

其中 `limit` 是历史上限，`lines` 是已保存的历史行数，`bytes` 是 tmux 报告的历史占用字节数，不代表 tmux 进程的全部内存。

### iTerm2：启用无限滚屏

打开 `Settings → Profiles → 选择使用的 Profile → Terminal`，建议启用：

- `Unlimited scrollback`
- `Save lines to scrollback when an app status bar is present`
- `Save lines to scrollback in alternate screen mode`

这些设置让 iTerm2 尽量保留显示历史。`Unlimited scrollback` 没有固定行数上限，内存占用会随输出增长；如果需要固定预算，也可以取消该项，把 `Scrollback lines` 设置为较大的数值，例如 `1000000`。配置含义见 [iTerm2 官方说明](https://iterm2.com/documentation-preferences-profiles-terminal.html)。

## 3. 建议关闭 iTerm2 的括号粘贴模式

对于主要由 Agent 发送命令、人工偶尔粘贴 IP、路径和短命令的运维 Profile，建议关闭：

`Settings → Profiles → 选择使用的 Profile → Terminal → Terminal may enable paste bracketing`

**取消勾选这一项。** 它是 Profile 级别的设置，使用该 Profile 的本地 Shell、SSH 和 tmux 都会受到影响。

括号粘贴模式会在粘贴内容前后附加 `ESC[200~` 和 `ESC[201~`，供 Shell 或编辑器识别整段粘贴。状态不一致时，这些标记可能残留为 `0~`、`1~`、`200~`、`201~` 等文字，导致粘贴后的 IP 或命令需要手工修正。

触发来源不只有 Vim，Shell 本身也可能启用这个模式。iTerm2 官方记录了 SSH 意外断开后模式未恢复的情况，但某一次故障的具体来源仍需要现场判断，不能仅凭乱码就归因于某个程序。原理与开关说明见 [iTerm2 官方文档](https://iterm2.com/documentation-one-page.html#terminal-may-enable-paste-bracketing)。

关闭后的主要影响是：

- IP、路径、普通单行文本通常没有明显变化。
- Shell 无法再依靠括号标记把整段粘贴作为一个整体处理；多行命令或末尾换行可能直接触发执行。
- Vim 等编辑器可能无法自动识别粘贴，出现自动缩进叠加或触发按键映射。
- 当前项目通过 `tmux send-keys -l` 发送命令，不经过 iTerm2 的剪贴板粘贴流程，因此不依赖这一能力。

这是针对上述运维场景的取舍；经常粘贴大段代码的其他 Profile 可以继续保留该功能。

### 保留功能时，临时恢复的方法

如果暂时保留此设置，出现首尾乱码时，可以在出问题的普通 Linux Shell 提示符下手动输入并执行：

```bash
printf '\033[?2004l'
```

这会发送关闭括号粘贴模式的控制序列，不修改配置文件，也不删除 tmux 历史。Shell 或其他程序之后仍可能重新启用它；它是临时恢复，不是永久禁用。输入前先清掉已有的异常内容，避免把乱码一起执行。如果复制这行命令也会带入乱码，直接手动敲入即可。

控制序列定义见 [XTerm 文档](https://invisible-island.net/xterm/xterm-paste64.html)。

## 4. 为 Codex TUI 配置良好的中文等宽字体

使用 Codex TUI 等终端 Agent 时，建议专门选择适合中文与西文混排的等宽字体，例如本项目维护者正在使用的 **Sarasa Mono SC（等距更纱黑体 SC）**，或 **Maple Mono CN**。

传统命令行常以英文命令、路径和日志为主，中文长文本的阅读体验容易被忽略。使用中文与 Agent 协作时，终端中会持续出现大段需求、分析、工具结果、代码变更说明和对话历史。终端也承担了长文本阅读界面的作用，字体的清晰度、字形一致性和中英文宽度关系会直接影响阅读体验。

### 为什么推荐 Sarasa Mono SC

Sarasa 将中日韩文字与拉丁、希腊、西里尔字母等组合在同一字体家族中，适合中文、日文、韩文、英文、法文、俄文和希腊文等多种语言混排。`Mono` 是等宽字型，`SC` 表示采用简体中文地区字形。官方中文说明也推荐编程用户选择 Mono SC，参见 [Sarasa Gothic 项目说明](https://github.com/be5invis/Sarasa-Gothic/blob/main/README.zh_CN.md)。

这里关注的是稳定的 **1:2 宽度关系：常见半角字母和数字占一列，中日韩全角字符占两列**。中文段落中夹杂 `remote:0.0`、文件路径、命令和代码时，宽度协调更便于阅读，也有利于表格、缩进和文本边框对齐。仅使用一款英文字体、让中文临时回退到另一款字体，可能出现字重、字号或基线不协调的问题。

### 另一种选择：Maple Mono CN

**Maple Mono CN** 同样适合大量中文与英文混排的终端场景，官方明确强调中英文宽度为 **2:1**，即一个中文全角字符对应两个英文半角字符的宽度。它采用偏圆润的字形，支持连字，可按个人阅读偏好与 Sarasa Mono SC 二选一。特性说明见 [Maple Mono 官方项目](https://github.com/subframe7536/maple-font)。

选择时注意版本后缀：

- `Maple Mono CN`：内置中文和日文字符。
- `Maple Mono NF CN`：在 CN 版本的基础上附带 Nerd Font 终端图标。

需要中英文统一显示时，选择带 `CN` 后缀的版本；只有 `NF` 后缀表示增加终端图标，不表示内置中文。字体包可从 [Maple Mono 发布页面](https://github.com/subframe7536/maple-font/releases) 下载。

### 在 iTerm2 中设置

1. 从 [Sarasa Gothic 发布页面](https://github.com/be5invis/Sarasa-Gothic/releases) 下载包含 Mono SC 的字体包，或从上面的 Maple Mono 发布页面下载 CN / NF CN 版本，解压后通过 macOS「字体册」安装需要的字体文件。
2. 打开 `Settings → Profiles → 选择运行 Codex TUI 的 Profile → Text`。
3. 将主字体设置为所选的 `Sarasa Mono SC`、`Maple Mono CN` 或 `Maple Mono NF CN`，按屏幕和阅读距离调整字号。
4. 如果启用了独立的 `Non-ASCII font`，也将它设为同一字体、同一字号，使中文和带重音的西文字母使用一致的字体配置。

字体应配置在**实际显示 Codex TUI 的本地终端 Profile** 中；它只改变显示效果，不需要在远端服务器安装，也不改变 Agent 读取的文字内容。iTerm2 的主字体与非 ASCII 字体设置见[官方说明](https://iterm2.com/documentation-preferences-profiles-text.html)。

可以用下面这组文本观察中英文、多语言、数字和路径混排的效果：

```text
中文说明：检查服务状态，并汇总今天的异常。
日本語 / 한국어 / English / français / Русский / Ελληνικά
目标 remote:0.0，文件 /var/log/app.log，状态 exit=0。
半角：ABCD1234
全角：中文等宽
```

最后两行冒号后的内容应呈现相同的总宽度。这里的 1:2 指常见半角与全角字符的关系，并不代表所有 Unicode 字符都占一列或两列；组合附加符、Emoji，以及希腊字母等宽度有歧义的字符还受终端和应用的宽度规则影响。若仍有错位，需要一并检查宽度设置，而不是只更换字体。

## 5. 用短别名管理默认会话

固定使用名为 `remote` 的本地会话，可以省去反复输入完整命令。下面这组别名来自本项目维护者的本地配置：

```bash
alias tn='tmux new -s remote'
alias ta='tmux attach -t remote'
alias tl='tmux ls'
alias tk='tmux kill-session -t remote'
```

| 命令 | 含义 |
| --- | --- |
| `tn` | 新建并进入 `remote` 会话 |
| `ta` | 连接已有的 `remote` 会话 |
| `tl` | 列出本地 tmux 会话 |
| `tk` | 删除整个 `remote` 会话，包括其窗口和 pane |

`tn` 不会覆盖同名会话，已经存在时会提示重复；`ta` 用于连接已有会话。`tk` 会结束该会话中的终端及 SSH 连接，不是退出显示界面，也不保证清理远端脱离终端运行的任务。

### zsh 配置

macOS 默认使用 zsh，将上面的别名加入 `~/.zshrc`，然后重新加载：

```bash
source ~/.zshrc
```

### 同时使用 bash 和 zsh

也可以沿用维护者的方式，把这四个别名统一放到 `~/.shell_common`，再让两个 Shell 的启动配置加载它：

```bash
if [ -f "$HOME/.shell_common" ]; then
  . "$HOME/.shell_common"
fi
```

zsh 将这段加入 `~/.zshrc`；bash 将它加入 `~/.bashrc`，登录 Shell 还需在 `~/.bash_profile` 中加载 `~/.bashrc`，或直接加载 `~/.shell_common`。如果已有加载关系，保留原来的方式，不必重复添加。

在本地 Shell 中检查别名：

```bash
type tn ta tl tk
```

## 6. AI Agent 采用完整权限

对于由熟悉业务和系统的运维人员维护的这套工作台，本文推荐将 AI Agent 配置为**完整权限（100% 权限），关闭工具执行层的逐次审批**。目标是让 Agent 连续完成工作，减少每条命令都点击确认带来的打断。

这项配置意味着主动接受 Agent 以当前系统用户的权限读写文件、执行命令和访问网络。安全性由操作者对业务、目标环境、影响范围和恢复手段的判断承担；不能把机械地确认每一次执行当作业务安全保障。完整权限不会自动赋予本机或远端的 root 权限，也不会绕过系统本身的访问控制。

### Codex 示例

在支持权限选择的客户端中选择 `Full access`。CLI 可以显式启动为：

```bash
codex --sandbox danger-full-access --ask-for-approval never
```

如需作为用户级默认设置，在 `~/.codex/config.toml` 的顶层添加或修改这两项，保留其他配置，避免重复定义：

```toml
sandbox_mode = "danger-full-access"
approval_policy = "never"
```

配置写在顶层，不能误放进 `[mcp_servers.…]` 或其他 TOML 表内。如果该配置文件由符号链接管理，应修改链接指向的源文件。

这是本指南针对工作台的推荐，不是 OpenAI 的默认安全建议。设置含义及客户端权限入口见 [OpenAI 官方文档](https://learn.chatgpt.com/docs/sandboxing)。其他 Agent 应选择其对应的完整权限、无需逐次工具审批模式，具体选项以该工具当前版本为准。

**Agent 工具执行权限与业务确认是两层机制。** 上述配置只调整客户端权限，不会取消项目脚本已有的生产确认或修改 `SKILL.md`；这些属于各自的业务执行规则，本文不作调整。

## 7. 使用注意事项

### 先准备好目标环境，再交给 Agent

在本地用 `tn` 创建会话后，自行完成远端登录、MFA、切换用户、进入工作目录和环境初始化。交给 Agent 时，明确说明目标 pane、生产或非生产环境，以及本次任务，例如：

```text
使用 tmux-remote-linux，目标 remote:0.0，环境 production。
已登录目标机器并切换到工作用户，请先读取当前终端，再检查今天 10:00 到 10:15 的服务错误日志。
```

默认目标是 `remote:0.0`。如果更换了窗口或拆分 pane，可以在本机查看实际目标：

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} command=#{pane_current_command}'
```

不要让 Agent 猜生产或非生产环境。切换机器、用户、目录、集群或 kubeconfig 后，也要把变化告诉它，便于重新确认上下文。

### 切换主机后，必须重新声明生产或非生产环境

同一个 tmux pane 中可能反复 SSH 到不同主机，也可能退出一层 SSH 后回到上一台机器。**`remote:0.0` 这个目标不变，不代表背后的主机或生产属性没有变化。尤其从非生产切换到生产，必须在下一条命令提交前明确告知 Agent，不能让它沿用之前的非生产上下文。** 从生产切回非生产，也应明确更新。

项目的 `REMOTE_TMUX_ENV` 是调用脚本时显式传入的环境标记，脚本不会根据 SSH 切换自动识别目标是否变成生产。如果实际已经进入生产，而 Agent 仍使用 `non-production`，脚本就不会触发生产确认。终端提示符或主机 IP 的变化也不能代替用户对环境属性的明确说明。

每次切换按以下顺序交接：

1. 先让 Agent 停止继续提交命令，确认当前任务的执行状态，再人工切换主机。
2. 切换完成后，明确告知当前 pane、目标主机、用户，以及 `production` 或 `non-production`；即使 pane 没变也要说明。
3. 让 Agent 更新后续本地脚本调用使用的 `REMOTE_TMUX_ENV`，先读取当前终端，重新核对目标和上下文，再继续任务。这里更新的是脚本调用环境，仅在远端 Shell 中 `export` 不会更新 Agent 本地的调用设置。
4. 进入生产后，后续命令按生产流程重新审核；切换前对旧目标的授权不能沿用到新目标。

可以直接这样告诉 Agent：

```text
我已将 remote:0.0 从非生产主机切换到生产主机 <主机名或 IP>，当前用户是 <用户名>。
后续环境改为 production，请停止沿用之前的非生产执行上下文。
先读取当前终端并核对目标，后续命令按生产流程审核后再提交。
```

**这一步必须发生在提交命令之前。** 命令一旦发出，可能已经修改数据、重启服务或向其他系统提交任务。后来补一句「这是生产」、按 `Control + C` 或关闭终端，都不能保证撤回已发生的操作，也不等于回滚。

### 用 Option 在应用选择与 iTerm2 选择之间切换

在 Codex TUI 或开启了 `mouse on` 的 tmux 界面中，鼠标事件可能由应用处理，双击选词和拖动选择的行为也由应用决定。**先按住 Option，再双击鼠标或触控板，可以临时使用 iTerm2 自带的选词功能；按住 Option 拖动则可使用 iTerm2 的文本选择。** 用 `ta` 或 `tmux attach` 返回 tmux 界面后，也可以这样操作。

iTerm2 官方说明：应用正在使用鼠标报告时，按住 Option 可以暂时绕过它来选择文本。iTerm2 默认选中即复制；如果关闭了该设置，选中后再按 `Command + C`。参见 [iTerm2 鼠标选择说明](https://iterm2.com/documentation-general-usage.html)。

例如屏幕上有下面这段命令：

```text
git rev-list --left-right --count HEAD...origin/main
```

在维护者当前的配置中，按住 Option 双击可以按 iTerm2 的选词规则完整选中 `rev-list` 或 `--left-right`；不按 Option 时，应用可能只选中 `rev`、`list` 等片段。具体选词边界取决于应用版本和 iTerm2 的配置，知道两种选择方式，可以在一种不顺手时换另一种。

**复制折行内容时，两种方式也有不同的优势。** 在维护者当前使用的 Codex TUI 中，应用自身的复制能把视觉上折成多行、原本属于同一逻辑行的内容还原为一行，很适合复制长命令和路径。按住 Option 使用 iTerm2 选择同一段内容时，可能把屏幕中的折行带成真正的换行，粘贴后就变成两行或更多行。

| 需要复制的内容 | 可以优先尝试 |
| --- | --- |
| 含连字符的单词、命令参数或一小段文字 | 按住 Option，使用 iTerm2 双击或拖动选择 |
| Codex 中显示折行、原本是一行的长命令或路径 | 使用 Codex 自身的选择与复制，保留逻辑行 |

上述折行差异是当前使用体验，不代表 iTerm2 的所有折行都会产生换行。iTerm2 能否合并取决于终端保存的换行信息；TUI 重绘后的屏幕行未必保留原始逻辑行。复制长命令后，留意是否带入额外换行，尤其是在已经关闭括号粘贴模式的情况下。

### 同一个 pane 同一时间只由一方输入

Agent 工作期间，人工不要同时在同一个 pane 输入命令；多个 Agent 也不要并发向同一个 pane 发送输入。输入可能拼接到一起，输出也可能被误认成另一条命令的结果。

推荐在准备好远端 Shell 后，按 `Control + b`，松开后再按 `d`，分离 tmux 会话，让 Agent 在后台操作。需要观察、输入敏感信息或主动接管时，用 `ta` 重新连接。分离只断开当前显示连接，会话及其中的程序继续运行；`tk` 则会删除会话，两者不同。

需要人工接管时，先明确让 Agent 停止继续提交命令，并确认当前命令的状态。人工操作完成后，说明做了哪些更改、当前处于什么提示符，再让 Agent 继续。若只是另外查看信息，可以使用独立的终端或 pane。

### 密码和验证码由用户直接输入

遇到 SSH 密码、MFA 验证码、令牌或其他敏感输入时，由用户直接在终端中输入，完成后告知 Agent。不要把这些内容粘贴到 AI 对话中，也不要让 Agent 把它们写进命令或临时脚本。

历史缓冲区设大后，旧输出会保留更久；项目默认也会记录本地审计日志。读取历史、分享日志或截图前，要注意其中是否包含密钥、凭据或业务敏感信息。

### 普通 Shell 与交互程序要区分

`tmux-remote-linux` 用于普通 Linux Shell。MySQL、Redis CLI、Python、Spark Shell、Oasis 等交互程序，以及 Vim、less、top 等全屏程序，具有各自的输入语法和状态，不适合继续通过普通 Shell 包装命令操作。

如果终端停在这些程序里，告诉 Agent 当前状态，改用对应的专用工具或 skill，或由人工处理到普通 Shell 后再交回。不要把 `mysql>`、`work>`、`>>>` 等提示符当成 Shell，也不要在这些提示符下粘贴本文的 Shell 恢复命令。

### 完整权限下仍要看清业务确认

完整权限减少的是客户端工具审批。项目现有的生产业务确认仍按批次进行：Agent 展示目标、整批命令、目的和影响后，用户在回复首行单独输入本批要求的数字。从第二行起可以补充业务背景、备注或下一步方向。

一次确认只覆盖展示的那批命令及其目标和上下文。命令改变、目标改变或重新提交时，需要重新确认。业务上有关联、且已经确定的命令可以一起审核；需要根据前一步结果才能确定的操作，应等结果出来后再审核。

审核重点是目标机器、用户、目录、集群、操作范围和恢复办法。AI 可能误解业务背景、别名或当前环境；数字回复只表达授权，不能代替这些判断。

### 慢命令和异常状态先判断，再恢复

远端网络、冷数据读取、下载和集群操作可能较慢。暂时没有新输出，不等于命令卡死。让 Agent 先读取终端、确认是否仍在运行，再决定等待或恢复，避免重复提交同一项操作。

同样，`Control + C`、关闭会话、重启服务、删除文件等动作都可能改变正在进行的任务。不要仅为了清爽的终端画面而打断程序。人工已经中断或切换过环境时，应先告知 Agent，让它重新检查状态。

### 大缓冲区用于保留上下文，读取仍应有范围

缓冲区大，不意味着每次都需要让 Agent 读取全部历史。排障时给出时间段、关键词、服务名或具体文件，通常更容易得到有效结果，也减少无关输出和 Token 消耗。

复杂操作可以让 Agent 先生成可审阅的临时脚本；普通文件传输使用对应的文件传输工具或 skill。终端历史和本地审计日志用于回看，不等同于完整备份，不能保证记录所有人工操作或恢复已删除的会话历史。
