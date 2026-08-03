# repair-secure-vultr-3xui

一个用于修复和加固 Vultr VPS 上 3x-ui/Xray/VLESS 服务的 Codex Skill。

它来自一次真实完成的恢复流程：在 3x-ui 更新后定位 VLESS/REALITY 客户端兼容问题，恢复 Ubuntu root 访问，建立只能转发管理面板的受限 SSH 账户，将 3x-ui 面板改为仅监听本机回环地址，并保留 VLESS 与订阅端口正常对外服务。

> 这是供 Codex 执行和协助排障的操作型 Skill，不是一键重装脚本。它强调先取证、先备份、逐步验证和保留回滚点。

## 适用场景

- 更新 3x-ui 后，Shadowrocket、v2ray 等客户端突然无法连接。
- 3x-ui 面板、订阅服务和 VLESS 入站需要分开诊断。
- 忘记 Ubuntu root 密码，需要通过 Vultr SystemRescue 恢复访问。
- 希望关闭 3x-ui 管理面板的公网入口，只通过 SSH 隧道管理。
- 希望为 macOS 生成双击即可打开面板的 `.command` 启动器。
- 为新的 Vultr 服务器建立可验证、可回滚的 3x-ui/VLESS 运维流程。

## 核心能力

- 只读检查 3x-ui、Xray、监听端口、日志和反向代理。
- 在首次修改前备份 3x-ui 数据库。
- 仅在日志和客户端版本支持该判断时处理 REALITY `minClientVer` 兼容问题。
- 使用 Vultr SystemRescue 安全恢复 root 密码，并把密码输入交还用户本人。
- 创建独立 Ed25519 密钥和 `panel-tunnel` 受限账户。
- 通过 `permitopen`、forced command 和禁止 shell，把账户限制为面板端口转发。
- 隧道验证成功后，再把 3x-ui 面板绑定到 `127.0.0.1`。
- 检查 Nginx、Caddy、Cloudflare 等是否仍在重新公开面板。
- 保留并验证 VLESS 与订阅端口，不盲目启用防火墙。
- 提供面板启动器生成脚本，支持 HTTP/HTTPS 以及不同的本地、远端端口。

## 安全原则

- 不在面板隧道验证成功前关闭公网面板。
- 不收集、保存或代替用户输入新密码。
- 不使用 Vultr 的 **Reinstall SSH Keys** 功能恢复密码，避免误触重装。
- 不通过 noVNC 手敲长公钥；使用精确文件传输并核对指纹。
- 不使用 `passwd -l` 锁定隧道账户，避免 Ubuntu sshd 拒绝有效公钥。
- 不随意修改 UUID、REALITY 密钥、short ID、SNI、端口或防火墙规则。
- 不把 TCP 端口可达误判为 Xray、TLS 或面板应用已经正常。

## 仓库结构

```text
repair-secure-vultr-3xui/
├── README.md
└── repair-secure-vultr-3xui/
    ├── SKILL.md
    ├── agents/
    │   └── openai.yaml
    ├── references/
    │   └── runbook.md
    └── scripts/
        └── make_panel_tunnel_command.sh
```

## 安装

### 让 Codex 安装

对 Codex 说：

```text
请安装 GitHub 仓库 Terrykaige/repair-secure-vultr-3xui 中
repair-secure-vultr-3xui 目录下的 Skill。
```

### 手动安装

```bash
git clone https://github.com/Terrykaige/repair-secure-vultr-3xui.git
mkdir -p ~/.codex/skills
cp -R repair-secure-vultr-3xui/repair-secure-vultr-3xui ~/.codex/skills/
```

安装后，Skill 主文件应位于：

```text
~/.codex/skills/repair-secure-vultr-3xui/SKILL.md
```

重新打开 Codex 任务后即可被发现。

## 使用方法

### 新服务器配置与加固

```text
使用 $repair-secure-vultr-3xui 检查并加固这台新的 Vultr 服务器。
我要使用 3x-ui/VLESS，并把管理面板限制为只能通过 SSH 隧道访问。
```

### 处理更新后断网

```text
使用 $repair-secure-vultr-3xui 诊断 3x-ui 更新后 VLESS 无法连接的问题。
客户端包括 Shadowrocket 和 Windows v2ray，请先只读检查并建立回滚点。
```

### 关闭管理面板公网访问

```text
使用 $repair-secure-vultr-3xui 为 3x-ui 配置受限 SSH 隧道。
确认隧道访问成功后，再关闭管理面板公网访问，并保留订阅和 VLESS 端口。
```

### 恢复 root 访问

```text
使用 $repair-secure-vultr-3xui 指导我通过 Vultr SystemRescue 恢复 Ubuntu root 密码。
密码输入步骤必须交给我本人完成。
```

## 标准执行顺序

1. 没有正常 shell 访问时，先通过 SystemRescue 恢复 root。
2. 分别检查面板、订阅和 VLESS/Xray 入站。
3. 在第一次修改前创建并验证数据库备份。
4. 只根据日志和客户端版本证据修复兼容性问题。
5. 创建并验证只能转发面板的 SSH 账户。
6. 保持公网面板开放，先证明隧道能返回登录页面。
7. 将面板绑定到 `127.0.0.1`，检查反向代理并重新验证。
8. 生成 macOS 启动器。
9. 验证代理、订阅、隧道、命令拒绝和回滚点。

## macOS 面板启动器

Skill 自带启动器生成脚本：

```bash
scripts/make_panel_tunnel_command.sh \
  SERVER_HOST REMOTE_PANEL_PORT LOCAL_PANEL_PORT PANEL_SCHEME \
  PANEL_BASE_PATH ABSOLUTE_PRIVATE_KEY_PATH OUTPUT.command
```

示例：

```bash
scripts/make_panel_tunnel_command.sh \
  example.com 28491 38491 https /panel/ \
  /Users/yourname/.ssh/vultr-panel-ed25519 \
  /Users/yourname/Desktop/打开3x-ui面板.command
```

启动器会：

1. 使用指定私钥建立本地到服务器面板端口的 SSH 隧道。
2. 等待 HTTP/HTTPS 探测成功。
3. 自动在默认浏览器打开面板。
4. 在终端窗口关闭或按下 `Control+C` 时断开隧道。

## 已验证内容

- Skill YAML、命名和目录结构通过官方 `quick_validate.py` 校验。
- 启动器生成脚本通过 Bash 和生成后 Zsh 语法检查。
- 验证了 HTTP/HTTPS、本地与远端不同端口以及非法参数拒绝。
- 运行手册只使用占位符和回环地址，不包含真实服务器配置、密码或密钥。

## 注意事项

- 3x-ui 和 Xray 的命令、默认值与数据库结构可能随版本变化；执行前必须核对服务器上的实际版本和官方源码。
- `minClientVer` 只是更新后断网的一种可能原因，不能作为默认结论。
- 如果使用 Nginx、Caddy、Cloudflare Tunnel 或其他反向代理，仅修改 3x-ui 监听地址可能不足以关闭公网入口。
- 本 Skill 不替代服务器备份、Vultr 快照、密钥保管和定期客户端更新。
- 仅用于你拥有或获得明确授权管理的服务器，并遵守适用的法律、服务条款和组织政策。
