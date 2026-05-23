# tz_router_opt

WARP-Go + Tailscale 路由优化脚本

## 部署 watchdog

```bash
git clone git@github.com:neohob/tz_router_opt.git /root/tz_router_opt
bash /root/tz_router_opt/deploy.sh
```

## WARP 域名名单路由

`warp-allowlist.txt` 是需要走 WARP 的域名后缀名单。每行一个域名，`#` 开头的行会被忽略。

当前用途：默认代理流量走 VPS 原生网卡 `eth0`，只有名单里的域名通过 sing-box 的 `warp-out` 出站走 WARP。

应用到 gktz1：

```bash
bash deploy-route.sh
```

常用流程：

```bash
vim warp-allowlist.txt
python3 -m unittest discover -s tests
bash deploy-route.sh
```

## 功能

- WARP-Go 自动恢复（掉线/半死/回原IP）
- Cloudflare CDN 绕过路由（解决 x.com、Discord 等 TLS 冲突）
- 自动换 IP（检测到 CF 站点不通时轮换 WARP IP，黑名单机制）
- Tailscale 路由修复（防止 WARP 劫持 100.64.0.0/10 流量）
- 清理重复 WARP 路由规则
- 保护 SSH 规则不被删除
- sing-box allowlist 路由：名单走 WARP，默认走 eth0
