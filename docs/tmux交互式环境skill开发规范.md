# tmux 交互式环境 Skill 开发规范

## 1. 背景

`tmux-remote-linux` 不应该被理解成“只能操作 Linux shell 的 skill”。它实际上包含两类能力：

1. **tmux transport 能力**
   - 读取 tmux pane 内容。
   - 向 tmux pane 发送按键。
   - 等待指定输出或 prompt。
   - 记录审计日志。
   - 管理目标 pane 和环境类型。

2. **Linux shell adapter 能力**
   - `run.sh` 面向 bash/zsh 这类标准 Linux shell。
   - 它会把命令 base64 包装后送到远端 shell。
   - 它依赖 shell 能执行 `printf`、变量、子进程、重定向等语义。
   - 它用 BEGIN/END marker 和 exit code 判定命令边界。

`tmux-oasis-cli`、`tmux-mysql`、`tmux-python`、`tmux-spark-shell` 等交互式环境，不应该复用 Linux shell adapter。它们应该复用 tmux transport 思想，然后实现自己的环境 adapter。

`tmux-*` 系列不限定目标必须是远程机器。只要交互式环境运行在 tmux pane 中，无论 pane 背后是本地进程、远程 shell、堡垒机后的主机，还是嵌套登录后的实例，都可以按照同一套 adapter 规范管理。

### 1.1 tmux target 串行性

同一个 tmux target 是一个串行交互通道。任何 `tmux-*` skill 都不得对同一个 target 并发发送命令或按键。

原因：

- 多个输入会在同一个 pane 中排队或交错。
- 输出边界会被污染，agent 可能把 A 命令的输出归属给 B 命令。
- REPL 状态、prompt、cwd、登录状态和 continuation 状态都可能被误判。

规则：

- 对同一个 tmux target，必须等待上一条脚本调用或恢复动作完成后，才能开始下一条。
- 不同 tmux target 原则上可以并行，但必须明确 target 不同。
- 这个规则适用于 `tmux-remote-linux`、`tmux-oasis-cli`、`tmux-mysql` 以及后续所有 `tmux-*` adapter。

## 2. 核心原则

### 2.1 降低模型成本

交互式环境 skill 的重要目标是减少 agent 和大模型的推理次数，防止模型误解当前环境。

确定性的工作应该下沉到脚本中，例如：

- 当前 prompt 和环境状态识别。
- 命令完成条件判断。
- 输出截取。
- 常见安全规则。
- 对错误环境的拒绝和推荐下一步 adapter。

大模型应该主要负责理解用户意图和选择工具，而不是反复猜测当前 prompt、复制大段输出、判断是否该切换 skill。

### 2.2 分层原则

每个交互式环境 skill 都应分成两层：

- **transport 层**：通过 tmux 读写终端。
- **adapter 层**：理解当前交互环境的 prompt、命令语法、命令完成条件和输出截取规则。

禁止在非 Linux shell 环境里直接套用 `tmux-remote-linux/run.sh` 的 shell 语义。

### 2.3 原生命令原则

adapter 只能向目标交互环境发送它原生支持的命令。

例如：

- Oasis CLI 中发送 `cluster describe <cluster-id>`。
- MySQL 中发送 SQL 和 MySQL client 命令，例如 `select 1;`、`\c`、`exit`。
- Python REPL 中发送 Python 表达式或语句。

不要在 MySQL、Oasis、Python、Spark shell 等 REPL 中发送 `printf`、`echo`、shell 变量、shell 重定向或 BEGIN/END marker。

### 2.4 Prompt 边界原则

每个 adapter 必须定义自己的命令完成条件。

常见例子：

- Linux shell：BEGIN/END marker 和 exit code。
- Oasis CLI：命令执行后重新出现 `work>`。
- MySQL：语句执行后重新出现 `mysql>`。
- Python REPL：命令执行后重新出现 `>>>`，`...` 表示多行未结束。
- Spark shell：命令执行后重新出现 `scala>` 或对应 shell prompt。

如果无法判断命令是否完成，脚本必须 timeout 并报告当前状态，不能伪造成功。

### 2.5 输出截取原则

adapter 必须尽量只返回本次命令的输出，不能直接 dump 大段历史。

推荐策略：

1. 发送目标环境的原生命令。
2. 等待目标环境 prompt 重新出现。
3. 根据命令 echo 或本次请求 marker 截取输出。
4. 对敏感信息做过滤。
5. 对过长输出做边界控制。

### 2.6 状态机原则

每个 adapter 必须识别当前 pane 状态，并明确每种状态允许什么操作。

推荐至少区分：

- `target_repl`：目标交互环境，例如 `mysql>` 或 Oasis `work>`。
- `continuation`：多行输入未结束，例如 MySQL `->`。
- `linux_shell`：外层 Linux shell。
- `unknown_interactive`：无法判断的交互环境。
- `busy_or_running`：没有 prompt，可能有前台命令正在运行。

不允许在未知状态下盲目发送命令。

### 2.7 失败处理原则

失败时必须保持保守：

- timeout 后只读 pane 判断状态。
- 不自动连续发送 `exit`、`Ctrl-C`、`kill` 等可能改变状态的操作。
- 不把 unknown 状态当作 shell 或目标 REPL。
- 报告当前 prompt、最近输出摘要、已发送的命令。

### 2.8 敏感信息原则

adapter 必须过滤本环境常见敏感信息。

例如：

- Oasis `instance login` 可能输出私钥。
- MySQL 查询可能输出密码、token、AK/SK、连接串、私钥字段。

默认规则应该保守。除非用户明确授权并且上下文安全，否则不要查询或打印敏感字段。

### 2.9 可组合原则

不同 adapter 可以顺序组合，但边界必须清楚。

例如：

```text
tmux-remote-linux -> 启动 mysql client
tmux-mysql -> 在 mysql> 中执行 SQL
tmux-mysql -> exit 返回 Linux shell
tmux-remote-linux -> 继续执行普通 shell 命令
```

adapter 不应该跨环境继续假设自己的语义仍然成立。

## 3. 标准脚本形态

每个交互环境 skill 建议提供以下脚本：

- `<env>_status.sh`：识别当前 pane 状态。
- `<env>_enter.sh`：从 Linux shell 进入目标交互环境。
- `<env>_run.sh`：执行目标环境原生命令，并用目标 prompt 判定完成。
- `<env>_exit.sh`：从目标交互环境退出到外层 shell。
- 结构化解析脚本：例如从表格输出转换成 TSV/JSON。
- 业务薄封装脚本：例如 `mysql_send_sql.sh`。

其中 `<env>_run.sh` 是 adapter 的核心，不等同于 `tmux-remote-linux/run.sh`。

第一版可以不实现所有脚本，但必须把边界写清楚。

## 4. 开发检查清单

开发一个新的交互式环境 skill 时，必须回答：

- 当前环境的 prompt 长什么样？
- 如何判断当前 pane 已经在该环境中？
- 如何从 Linux shell 进入该环境？
- 如何退出该环境？
- 一条命令什么时候算完成？
- 输出如何截取？
- timeout 后应该如何报告？
- 当前环境会输出哪些敏感信息？
- 哪些命令是只读的？
- 哪些命令有副作用或破坏性，需要用户确认？
- 进入其他环境后，应该把控制权交给哪个 adapter？

## 4.1 写操作确认

如果目标 REPL 支持数据修改，不能简单沿用 Linux shell 的生产/非生产模型。

以 MySQL 为例，`insert`、`update`、`delete` 即使在测试或预发环境也可能非常危险：

- 测试库不一定有备份。
- 关联数据人工重建成本高。
- 一条错误 `update` / `delete` 可以破坏大量数据。
- 一条错误 `insert` 也可能污染状态机、唯一键或测试基线。

因此这类 REPL adapter 应设计自己的写操作确认协议。

推荐规则：

- 写操作默认需要人工确认，不依赖生产/非生产环境。
- 每条写命令单独确认。
- 使用随机单数字 challenge，降低用户无意识确认的概率。
- agent 必须展示目标、操作内容和一句风险说明。
- 脚本必须校验 approval 环境变量，防止 agent 绕过确认。
- approval 变量只能由用户当前对话回复中继而来，不能由 agent 自行设置。
- 如果目标语言像 SQL 一样有字符串、标识符引用、注释和转义规则，脚本只能声明并接受一个保守子集；不要把自写 scanner 伪装成完整语法树 parser。
- 对 MySQL 这类环境，优先拒绝注释、双引号字符串、反斜杠字符串转义和复杂多语句，而不是试图猜测 SQL mode。

推荐展示格式：

```text
**<环境>写操作确认**：**目标** `<tmux-target>`
**说明**：`<一句中文说明>`
**命令/SQL**：`<exact command>`
**同意执行请只回复数字** `<digit>`
```

## 5. 反例

以下做法禁止作为交互式环境 adapter 的通用方案：

- 在非 shell REPL 里发送 `printf BEGIN/END` 来伪造 shell marker。
- 在非 shell REPL 里使用 `tmux-remote-linux/run.sh`。
- 假设非 shell REPL 有 Unix exit code。
- 在 unknown 状态下发送 `exit` 试图恢复。
- 直接输出包含私钥、token、密码的大段 pane 历史。

## 6. 目标效果

最终每个特殊交互环境都应达到：

- agent 知道当前处于什么环境。
- agent 只发送该环境原生命令。
- 命令输出边界清晰。
- timeout 和异常可诊断。
- 敏感信息默认过滤。
- 可以和 `tmux-remote-linux` 的 Linux shell 能力自然组合。
