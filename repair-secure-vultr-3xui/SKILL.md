---
name: repair-secure-vultr-3xui
description: Repair and harden Vultr VPS deployments running 3x-ui/Xray with VLESS, especially after a 3x-ui upgrade causes client connection failures; recover a lost Ubuntu root password through Vultr SystemRescue; create a key-only, tunnel-only SSH account; bind the 3x-ui management panel to localhost; preserve VLESS and subscription ports; generate a macOS one-click panel launcher; and verify the final state. Use for Vultr, 3x-ui, VLESS/REALITY, Shadowrocket, v2ray clients, inaccessible panels, public panel exposure, SSH tunneling, or root recovery tasks.
---

# Repair and Secure Vultr 3x-ui

Use an evidence-first sequence that preserves proxy service and prevents lockout.

## Required preparation

1. Read [references/runbook.md](references/runbook.md) completely before changing server state.
2. Collect the server IP, OS, panel port, panel base path, subscription port, inbound ports, 3x-ui/Xray versions, client apps, and current access method.
3. Verify current 3x-ui CLI syntax against the installed binary and current official MHSanaei/3x-ui source before changing `listenIP` or version-sensitive settings.
4. State success criteria and the rollback point before execution.

## Non-negotiable rules

- Start with read-only checks. Separate panel failure, subscription failure, and proxy-inbound failure.
- Never close the public panel until a restricted SSH tunnel returns the panel successfully.
- Bind the panel service to loopback; do not blindly enable a firewall that could block SSH, VLESS, or subscriptions.
- Audit Nginx, Caddy, Cloudflare, and other reverse proxies; loopback binding alone does not close a proxy that intentionally republishes the panel.
- Keep VLESS and subscription listeners public unless the user explicitly requests otherwise.
- Never type, paste, store, or submit a user's new password. Stop at password prompts and hand control to the user.
- Never use Vultr **Reinstall SSH Keys** for password recovery; it can reinstall the server and destroy data.
- Do not use `passwd -l` for the tunnel user on Ubuntu: a locked account can cause sshd to reject a valid public key.
- The SSH filename is exactly `authorized_keys`. Avoid composing it or long public keys through noVNC; transfer the key with `scp` or another exact file-transfer method.
- Preserve existing unrelated configuration and create a dated database backup before changing 3x-ui settings.
- Treat direct port tests as secondary to server-side `ss -ltnp` evidence and successful application-layer checks.

## Execution outline

Follow the runbook gates in this order, skipping root recovery when working shell access already exists:

1. Recover root through SystemRescue first if normal SSH/console access is unavailable.
2. Baseline services, listeners, logs, client behavior, and reverse proxies.
3. Back up 3x-ui before the first configuration mutation.
4. Repair VLESS/REALITY compatibility only when logs and client versions support that diagnosis.
5. Create and verify the restricted `panel-tunnel` account.
6. Prove the tunnel while the public panel still works.
7. Bind `webListen` to `127.0.0.1`, restart, and verify.
8. Generate the macOS launcher with `scripts/make_panel_tunnel_command.sh`.
9. Verify service health, loopback-only panel listening, reverse-proxy closure, public proxy ports, command denial, and rollback readiness.

## Launcher generator

Run:

```bash
bash scripts/make_panel_tunnel_command.sh \
  SERVER_HOST REMOTE_PANEL_PORT LOCAL_PANEL_PORT PANEL_SCHEME \
  PANEL_BASE_PATH ABSOLUTE_PRIVATE_KEY_PATH OUTPUT.command
```

The generated launcher keeps the tunnel in the foreground, opens the panel only after an HTTP or HTTPS probe succeeds, and removes the tunnel when its terminal closes.

## Completion report

Report:

- confirmed cause and evidence;
- exact settings changed and backup location;
- tunnel key fingerprint, without exposing private key material;
- panel loopback listener and application-layer tunnel result;
- public reachability of each intended VLESS/subscription port;
- public panel result;
- launcher path and usage;
- any remaining risk, especially root password SSH or public subscription URLs.
