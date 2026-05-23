#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path
from typing import Any


GOOGLE_WARP_CIDRS = [
    "64.233.160.0/19",
    "74.125.0.0/16",
    "108.177.0.0/17",
    "142.250.0.0/15",
    "142.251.0.0/16",
    "172.217.0.0/16",
    "172.253.0.0/16",
    "216.239.32.0/19",
]


def read_allowlist(path: Path) -> list[str]:
    domains: list[str] = []
    seen: set[str] = set()

    for raw in path.read_text().splitlines():
        line = raw.strip().lower()
        if not line or line.startswith("#"):
            continue
        if line.startswith("*."):
            line = line[2:]
        if line not in seen:
            seen.add(line)
            domains.append(line)

    if not domains:
        raise ValueError(f"allowlist is empty: {path}")

    return domains


def tag_exists(cfg: dict[str, Any], tag: str) -> bool:
    for key in ("outbounds", "endpoints"):
        for item in cfg.get(key, []):
            if item.get("tag") == tag:
                return True
    return False


def patch_config(
    cfg: dict[str, Any],
    domains: list[str],
    *,
    warp_tag: str,
    default_interface: str,
) -> dict[str, Any]:
    if not tag_exists(cfg, warp_tag):
        raise ValueError(f"missing sing-box outbound/endpoint tag: {warp_tag}")

    direct_count = 0
    for outbound in cfg.get("outbounds", []):
        if outbound.get("type") == "direct" and "detour" not in outbound:
            outbound["bind_interface"] = default_interface
            direct_count += 1

    if direct_count == 0:
        raise ValueError("no direct outbounds found")

    route = cfg.setdefault("route", {})
    rules = route.get("rules", [])
    rules = [
        rule
        for rule in rules
        if not (
            rule.get("outbound") == warp_tag
            and (
                rule.get("domain_suffix") == domains
                or rule.get("ip_cidr") == GOOGLE_WARP_CIDRS
            )
        )
    ]

    insert_at = 1 if rules and rules[0].get("action") == "sniff" else 0
    rules.insert(insert_at, {
        "domain_suffix": domains,
        "outbound": warp_tag,
    })
    rules.insert(insert_at + 1, {
        "ip_cidr": GOOGLE_WARP_CIDRS,
        "outbound": warp_tag,
    })

    route["rules"] = rules
    return cfg


def write_json_atomic(path: Path, cfg: dict[str, Any]) -> None:
    data = json.dumps(cfg, ensure_ascii=False, indent=2) + "\n"
    with tempfile.NamedTemporaryFile("w", dir=str(path.parent), delete=False) as tmp:
        tmp.write(data)
        tmp_path = Path(tmp.name)
    os.replace(tmp_path, path)


def main() -> int:
    parser = argparse.ArgumentParser(description="Sync sing-box WARP allowlist routing")
    parser.add_argument("--config", default="/etc/s-box/sb.json", help="sing-box config path")
    parser.add_argument("--allowlist", default="warp-allowlist.txt", help="domain suffix allowlist path")
    parser.add_argument("--warp-tag", default="warp-out", help="sing-box WARP outbound/endpoint tag")
    parser.add_argument("--default-interface", default="eth0", help="interface for non-allowlisted direct traffic")
    parser.add_argument("--dry-run", action="store_true", help="print patched config without writing")
    args = parser.parse_args()

    config_path = Path(args.config)
    allowlist_path = Path(args.allowlist)
    cfg = json.loads(config_path.read_text())
    domains = read_allowlist(allowlist_path)
    patched = patch_config(
        cfg,
        domains,
        warp_tag=args.warp_tag,
        default_interface=args.default_interface,
    )

    if args.dry_run:
        print(json.dumps(patched, ensure_ascii=False, indent=2))
    else:
        write_json_atomic(config_path, patched)
        print(f"synced {len(domains)} WARP allowlist domains to {config_path}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
