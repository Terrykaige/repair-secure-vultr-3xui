# Vultr 3x-ui/VLESS Recovery and Hardening Runbook

## Contents

1. Safety and variables
2. Baseline diagnosis
3. Repair upgrade-related VLESS failure
4. Recover Ubuntu root access with SystemRescue
5. Create a restricted panel tunnel account
6. Close public panel access
7. Verify and roll back

## 1. Safety and variables

Obtain explicit authorization before persistent access changes, rebooting, attaching or removing rescue media, changing authentication, or closing public access.

Record these values; never silently reuse values from a different server:

```text
SERVER_HOST=
SSH_PORT=22
PANEL_PORT=
LOCAL_PANEL_PORT=
PANEL_SCHEME=http|https
PANEL_BASE_PATH=/.../
SUBSCRIPTION_PORT=
VLESS_PORTS=
SERVER_OS=
XUI_VERSION=
XRAY_VERSION=
REVERSE_PROXY=none|nginx|caddy|cloudflare|other
```

Success requires all of the following:

- intended VLESS clients connect;
- 3x-ui is active;
- the panel listens only on `127.0.0.1:PANEL_PORT`;
- the restricted SSH tunnel returns HTTP 200 or the expected login response;
- ordinary commands through the tunnel key are denied;
- intended VLESS and subscription ports remain public;
- the public panel cannot complete HTTPS;
- no configured reverse proxy republishes the panel;
- the configuration database backup exists.

## 2. Baseline diagnosis

If no working shell access exists, perform section 4 first, return here after normal Ubuntu boots, and then run read-only checks:

```bash
systemctl is-active x-ui
systemctl status x-ui --no-pager
ss -ltnp
journalctl -u x-ui -n 100 --no-pager
```

From a separate machine, test TCP reachability for SSH, the panel, subscription port, and each VLESS inbound. Then perform application-layer checks where possible. A reachable TCP port does not prove Xray or TLS is healthy.

Keep these fault domains separate:

- **Panel:** 3x-ui web process, TLS certificate, base path, panel listener.
- **Subscription:** subscription listener, URI path/token, reverse proxy if present.
- **Proxy:** Xray process, inbound port, UUID, REALITY keys, short ID, flow, transport, client compatibility.

Do not reinstall or reset configurations while services and listeners are healthy.

Inspect Nginx, Caddy, Cloudflare tunnels/proxies, and Vultr Firewall rules when present. Record any route that forwards a public hostname or port to the panel.

Before the first 3x-ui setting or inbound mutation, create and verify a dated backup:

```bash
cp -a /etc/x-ui/x-ui.db /root/x-ui.db.before-repair-YYYYMMDD-HHMMSS
ls -l /root/x-ui.db.before-repair-YYYYMMDD-HHMMSS
```

## 3. Repair upgrade-related VLESS failure

After a 3x-ui/Xray update, inspect Xray and 3x-ui logs for compatibility warnings. Compare the installed Xray version, the REALITY `minClientVer` value, and actual Shadowrocket/v2ray client core versions. Treat `minClientVer` as one possible cause, never the default diagnosis.

If logs explicitly show older clients are refused because REALITY now defaults to a newer minimum client version:

1. Prefer updating clients first.
2. If the installed clients cannot be updated immediately and the user accepts the compatibility tradeoff, set REALITY `minClientVer` to `0.0.0` for the affected inbound.
3. Restart only the required service/inbound.
4. Test a custom client node before switching the user's active node.
5. Verify the public egress IP and an HTTPS request through the proxy.

Do not change UUIDs, REALITY private/public keys, short IDs, SNI, or ports unless evidence identifies them as wrong.

## 4. Recover Ubuntu root access with SystemRescue

Use this only when normal SSH and console authentication are unavailable.

1. In Vultr, attach the official SystemRescue ISO and reboot.
2. Open noVNC and boot the default SystemRescue entry.
3. Identify the root partition; never assume its device name:

```bash
lsblk -o NAME,FSTYPE,SIZE,MOUNTPOINTS,LABEL,UUID
```

4. Mount the likely Linux root partition and confirm it before chrooting:

```bash
mount /dev/vda2 /mnt
sed -n '1,12p' /mnt/etc/os-release
```

Replace `/dev/vda2` with the partition proven by `lsblk` and `os-release`.

5. Bind required filesystems and enter the installed system:

```bash
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run
chroot /mnt /bin/bash
```

6. Run `passwd root`, stop at `New password:`, and let the user type and confirm the new password personally. Password input is intentionally invisible.
7. After `password updated successfully`, exit and unmount in reverse order:

```bash
exit
umount /mnt/run
umount /mnt/sys
umount /mnt/proc
umount /mnt/dev
umount /mnt
```

8. Remove the ISO in Vultr, allow the required reboot, and verify ports 22 plus intended proxy ports.
9. Let the user log in once through noVNC with the new password; do not ask them to disclose it.

Official reference: <https://docs.vultr.com/how-to-reset-the-root-password-of-a-vultr-compute-instance>

## 5. Create a restricted panel tunnel account

### 5.1 Generate a dedicated local key

Use a new per-server Ed25519 key, not an existing personal identity:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/vultr-panel-ed25519 -C vultr-panel-tunnel-SERVER_HOST
ssh-keygen -lf ~/.ssh/vultr-panel-ed25519.pub
```

Record the fingerprint. Keep the private key mode `600`.

If the key has a passphrase, load it into `ssh-agent` or the macOS Keychain before using `BatchMode=yes`. Otherwise the non-interactive launcher will fail. An unencrypted dedicated tunnel key is acceptable only when the user approves and file permissions remain `600`.

### 5.2 Create an unlocked but password-unusable account

On Ubuntu 22.04, the following tested pattern avoids sshd rejecting a locked account while leaving no usable password:

```bash
useradd -m -s /bin/bash panel-tunnel
usermod -p np panel-tunnel
passwd -S panel-tunnel
```

Expect status `P`, not `L`. The literal invalid hash `np` cannot match a normal password hash. Do not run `passwd -l panel-tunnel`.

### 5.3 Transfer the public key exactly

Avoid typing a long key in noVNC. From the local machine:

```bash
scp ~/.ssh/vultr-panel-ed25519.pub root@SERVER_HOST:/tmp/panel-tunnel.pub
```

Then on the server:

```bash
install -d -m 700 -o panel-tunnel -g panel-tunnel /home/panel-tunnel/.ssh
install -m 600 -o panel-tunnel -g panel-tunnel /tmp/panel-tunnel.pub /home/panel-tunnel/.ssh/authorized_keys
sed -i '1s@^@restrict,port-forwarding,permitopen="127.0.0.1:PANEL_PORT",command="/bin/false" @' /home/panel-tunnel/.ssh/authorized_keys
rm /tmp/panel-tunnel.pub
namei -l /home/panel-tunnel/.ssh/authorized_keys
ssh-keygen -lf /home/panel-tunnel/.ssh/authorized_keys
```

Compare the server fingerprint with the local fingerprint. The filename must contain an underscore: `authorized_keys`.

### 5.4 Prove the tunnel before closing the panel

From the local machine:

```bash
ssh -i ~/.ssh/vultr-panel-ed25519 \
  -o BatchMode=yes \
  -o IdentitiesOnly=yes \
  -o ExitOnForwardFailure=yes \
  -N \
  -L 127.0.0.1:LOCAL_PANEL_PORT:127.0.0.1:PANEL_PORT \
  panel-tunnel@SERVER_HOST
```

Keep it running and test:

```bash
curl -k -sS -o /dev/null -w '%{http_code}\n' \
  PANEL_SCHEME://127.0.0.1:LOCAL_PANEL_PORT/PANEL_BASE_PATH/
```

Expect the panel response. In a separate command, try an ordinary SSH command; authentication should succeed but the forced `/bin/false` command should return exit code `1` with no shell access.

## 6. Close public panel access

Use the installed binary and verify syntax against the installed version. Current official source exposes `setting -listenIP` and `setting -getListen`:

```bash
/usr/local/x-ui/x-ui setting -getListen
```

Use the earlier repair backup as the global rollback point. Create an additional fresh backup immediately before the listener change when other repairs have occurred since that backup:

```bash
cp -a /etc/x-ui/x-ui.db /root/x-ui.db.before-localhost-YYYYMMDD-HHMMSS
```

Set loopback and restart:

```bash
/usr/local/x-ui/x-ui setting -listenIP 127.0.0.1
systemctl restart x-ui
systemctl is-active x-ui
/usr/local/x-ui/x-ui setting -getListen
ss -ltnp
```

Authoritative server evidence must show:

```text
127.0.0.1:PANEL_PORT
```

The VLESS and subscription listeners should remain on their intended public addresses/ports.

If a reverse proxy exists, remove or restrict the public panel route separately and verify its hostname from an external machine. Do not alter a reverse proxy route used by the subscription service without proving that the subscription listener is independent in the installed version.

Official references:

- <https://github.com/MHSanaei/3x-ui/blob/main/main.go>
- <https://github.com/MHSanaei/3x-ui/blob/main/docs/content/docs/en/config/panel.mdx>

## 7. Verify and roll back

Run final checks from outside the server:

- SSH port reachable.
- Every intended VLESS/subscription port reachable.
- Tunnel panel request succeeds.
- Direct public panel HTTPS fails.
- Normal commands through `panel-tunnel` fail with forced command exit code `1`.

Run final checks on the server:

```bash
systemctl is-active x-ui
/usr/local/x-ui/x-ui setting -getListen
ss -ltnp
```

If the panel fails after changing the listener, keep the existing root/noVNC session open. Prefer restoring the recorded previous `listenIP` with the installed version's supported command. Restore the dated database only as a fallback, because it also overwrites settings changed after the backup:

```bash
systemctl stop x-ui
cp -a /root/x-ui.db.before-localhost-YYYYMMDD-HHMMSS /etc/x-ui/x-ui.db
systemctl start x-ui
```

Do not delete backups or disable root access during the same change window. Log out of noVNC after verification.
