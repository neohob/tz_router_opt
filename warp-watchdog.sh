#!/bin/bash
# tz_router_opt - WARP-Go Watchdog v5
# - Auto-recovers WARP tunnel
# - Never deletes SSH routing rules
# - Monitors x.com, Discord, Google, YouTube, GitHub for WARP IP restrictions
# - Auto-rotates IP when restrictions detected
# - Cloudflare CDN bypass routes
# - Tailscale routing fix (100.64.0.0/10 not hijacked by WARP)
# - Cleanup duplicate WARP routing rules

CONF="/usr/local/bin/warp.conf"
LOG="/root/warpip/warp_log.txt"
BAD_IPS_FILE="/root/warpip/bad_warp_ips.txt"
GOOD_IP_FILE="/root/warpip/last_good_ip.txt"

ORIGINAL_IP=$(grep -oP 'PostUp.*?ip -4 rule add from \K[0-9.]+' "$CONF" 2>/dev/null | head -1)

mkdir -p /root/warpip
touch "$BAD_IPS_FILE"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG"
}

# ============================================================
# WARP Status Checks
# ============================================================

check_warp_ip() {
    local ip
    ip=$(curl -s4m5 https://ifconfig.me 2>/dev/null)
    if [ -z "$ip" ]; then
        echo "dead"
        return
    fi
    if [ "$ip" = "$ORIGINAL_IP" ]; then
        echo "original"
        return
    fi
    echo "$ip"
}

check_network() {
    if ping -c 1 -W 3 1.1.1.1 >/dev/null 2>&1; then
        echo "ok"
        return
    fi
    echo "dead"
}

# Check known sites for WARP IP restrictions
# Returns "ok" or "blocked (site reason)"
check_sites() {
    # x.com / Discord: TLS failure → code 000
    for site in https://x.com https://discord.com; do
        code=$(curl -s4m8 -o /dev/null -w "%{http_code}" "$site" 2>/dev/null)
        if [ "$code" = "000" ] || [ -z "$code" ]; then
            echo "blocked ($site TLS失败)"
            return
        fi
    done

    # Google / YouTube: should return 200 or 3xx, not block
    for site in https://www.google.com https://www.youtube.com; do
        code=$(curl -s4m8 -o /dev/null -w "%{http_code}" "$site" 2>/dev/null)
        if [ "$code" = "000" ] || [ -z "$code" ]; then
            echo "blocked ($site 无响应)"
            return
        fi
    done

    # GitHub API: rate limit = 403 with "rate limit" message
    gh_code=$(curl -s4m8 -o /tmp/gh_check.json -w "%{http_code}" https://api.github.com/rate_limit 2>/dev/null)
    if [ "$gh_code" = "403" ]; then
        echo "blocked (GitHub API 限流)"
        return
    elif [ "$gh_code" = "000" ] || [ -z "$gh_code" ]; then
        echo "blocked (GitHub 无响应)"
        return
    fi

    echo "ok"
}

is_bad_ip() {
    grep -qF "$1" "$BAD_IPS_FILE" 2>/dev/null
}

add_bad_ip() {
    local ip="$1"
    if ! is_bad_ip "$ip"; then
        echo "$ip" >> "$BAD_IPS_FILE"
        log "记录不良WARP IP: $ip"
        tail -20 "$BAD_IPS_FILE" > "${BAD_IPS_FILE}.tmp" && mv "${BAD_IPS_FILE}.tmp" "$BAD_IPS_FILE"
    fi
}

save_good_ip() {
    echo "$1" > "$GOOD_IP_FILE"
}

get_last_good_ip() {
    cat "$GOOD_IP_FILE" 2>/dev/null
}

# ============================================================
# Routing: Cleanup, CF Bypass, Tailscale Fix
# ============================================================

cleanup_warp_rules() {
    log "清理重复 WARP 路由规则 (保留 SSH 规则)..."

    local count_before
    count_before=$(ip rule list | wc -l)

    local first_suppress="" first_warp=""

    ip rule list | grep -E 'lookup 50000|suppress_prefixlength' | while read -r rule; do
        pri=$(echo "$rule" | grep -oP '^\d+')
        [ -z "$pri" ] && continue

        if echo "$rule" | grep -q 'suppress_prefixlength'; then
            if [ -z "$first_suppress" ]; then
                first_suppress="$pri"
            else
                ip rule del priority "$pri" 2>/dev/null
            fi
        elif echo "$rule" | grep -q 'lookup 50000'; then
            if [ -z "$first_warp" ]; then
                first_warp="$pri"
            else
                ip rule del priority "$pri" 2>/dev/null
            fi
        fi
    done

    if [ -n "$ORIGINAL_IP" ]; then
        local main_count
        main_count=$(ip rule list | grep "from $ORIGINAL_IP lookup main" | wc -l)
        if [ "$main_count" -gt 2 ]; then
            while ip rule del from "$ORIGINAL_IP" lookup main 2>/dev/null; do :; done
            ip rule add from "$ORIGINAL_IP" lookup main
            ip rule add from "$ORIGINAL_IP" lookup main
        fi
    fi

    local count_after
    count_after=$(ip rule list | wc -l)
    log "路由规则: $count_before -> $count_after"
}

add_cf_bypass() {
    local GW iface
    GW=$(ip route show table main | grep default | awk '{print $3}')
    iface=$(ip route show table main | grep default | awk '{print $5}' | head -1)
    [ -z "$GW" ] && return
    [ -z "$iface" ] && iface="eth0"

    for net in 104.16.0.0/12 162.159.0.0/16 172.64.0.0/13 173.245.48.0/20 \
               103.21.244.0/22 103.22.200.0/22 103.31.4.0/22 141.101.64.0/18 \
               108.162.192.0/18 190.93.240.0/20 188.114.96.0/20 \
               197.234.240.0/22 198.41.128.0/17; do
        ip route replace $net via $GW dev $iface 2>/dev/null
    done
    log "Cloudflare CDN 绕过路由已添加"
}

fix_tailscale_route() {
    if ! ip rule list | grep -q '5174.*100\.64\.0\.0/10.*lookup 52'; then
        ip rule add to 100.64.0.0/10 lookup 52 priority 5174 2>/dev/null
        log "Tailscale 路由规则已添加 (priority 5174)"
    fi
}

# ============================================================
# WARP Restart / IP Rotation
# ============================================================

restart_warp() {
    log "重启 warp-go..."

    systemctl stop warp-go 2>/dev/null
    killall -9 warp-go 2>/dev/null
    sleep 1

    cleanup_warp_rules

    ip link del WARP 2>/dev/null

    systemctl start warp-go 2>/dev/null
    sleep 3

    if pgrep -x warp-go >/dev/null; then
        log "warp-go 已启动"
    else
        log "ERROR: warp-go 启动失败!"
    fi

    add_cf_bypass
    fix_tailscale_route
}

# Restart warp-go until we get a clean IP (max 5 tries)
# If all 5 fail, keep the last IP that passed the most checks
rotate_warp_ip() {
    local best_ip="" best_score=0

    local i=0
    while [ $i -lt 5 ]; do
        i=$((i+1))
        log "换IP尝试 $i/5..."
        restart_warp
        sleep 3

        local warp_ip
        warp_ip=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k 2>/dev/null | grep -oP 'ip=\K[0-9.]+')

        if [ -z "$warp_ip" ]; then
            log "换IP失败: 无法获取WARP IP"
            continue
        fi

        if is_bad_ip "$warp_ip"; then
            log "换到的IP $warp_ip 在黑名单中，继续换..."
            continue
        fi

        local site_status
        site_status=$(check_sites)
        if [ "$site_status" = "ok" ]; then
            log "换IP成功: $warp_ip (所有站点正常)"
            save_good_ip "$warp_ip"
            return 0
        else
            log "IP $warp_ip $site_status，尝试下一个..."
        fi
    done

    log "WARN: 5次换IP均有限制，保持当前状态"
    return 1
}

# ============================================================
# Main Loop
# ============================================================

log "=== WARP Watchdog v5 启动 ==="
log "原始IP: $ORIGINAL_IP"

add_cf_bypass
fix_tailscale_route

# Save initial good IP
current_ip=$(check_warp_ip)
if [ "$current_ip" != "dead" ] && [ "$current_ip" != "original" ]; then
    save_good_ip "$current_ip"
fi

while true; do
    net_status=$(check_network)

    if [ "$net_status" = "dead" ]; then
        log "ALERT: 网络不通，尝试恢复..."
        restart_warp
        sleep 10

        net_status=$(check_network)
        if [ "$net_status" = "dead" ]; then
            log "ERROR: 恢复失败，60秒后重试"
            sleep 60
            restart_warp
            sleep 10
        fi
    else
        ip_status=$(check_warp_ip)

        if [ "$ip_status" = "dead" ]; then
            log "WARN: WARP半死(ping通但无IP)，重启中..."
            restart_warp
            sleep 10
        elif [ "$ip_status" = "original" ]; then
            log "WARN: WARP断开，IP回原始，重启中..."
            restart_warp
            sleep 10
        else
            current_ip="$ip_status"
            if is_bad_ip "$current_ip"; then
                log "WARN: 当前WARP IP $current_ip 在黑名单中，换IP..."
                rotate_warp_ip
                sleep 10
            else
                site_status=$(check_sites)
                if echo "$site_status" | grep -q "blocked"; then
                    log "WARN: 站点受限($site_status)，IP $current_ip，换IP..."
                    add_bad_ip "$current_ip"
                    rotate_warp_ip
                    sleep 10
                else
                    save_good_ip "$current_ip"
                    sleep 120
                    continue
                fi
            fi
        fi
    fi

    sleep 60
done
