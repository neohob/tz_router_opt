# tz_router_opt

WARP-Go + Tailscale 路由优化脚本

## 部署

```bash
git clone git@github.com:neohob/tz_router_opt.git /root/tz_router_opt
bash /root/tz_router_opt/deploy.sh
```

## 功能

- WARP-Go 自动恢复（掉线/半死/回原IP）
- Cloudflare CDN 绕过路由（解决 x.com、Discord 等 TLS 冲突）
- 自动换 IP（检测到 CF 站点不通时轮换 WARP IP，黑名单机制）
- Tailscale 路由修复（防止 WARP 劫持 100.64.0.0/10 流量）
- 清理重复 WARP 路由规则
- 保护 SSH 规则不被删除
