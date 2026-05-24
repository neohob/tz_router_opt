import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]
SCRIPT = REPO / "sync-singbox-route.py"


class SyncSingboxRouteTest(unittest.TestCase):
    def test_syncer_binds_direct_and_inserts_warp_rule(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            config = tmp / "sb.json"
            allowlist = tmp / "warp-allowlist.txt"

            config.write_text(json.dumps({
                "endpoints": [{"type": "wireguard", "tag": "warp-out"}],
                "outbounds": [
                    {"type": "direct", "tag": "direct", "domain_strategy": "prefer_ipv4"},
                    {"type": "direct", "tag": "vps-outbound-v4", "domain_strategy": "prefer_ipv4"},
                    {"type": "direct", "tag": "vps-outbound-v6", "domain_strategy": "prefer_ipv6"},
                    {"type": "direct", "tag": "warp-IPv4-out", "detour": "warp-out"},
                ],
                "route": {
                    "rules": [
                        {"action": "sniff"},
                        {"outbound": "warp-out", "domain_suffix": ["stale.example"]},
                        {"outbound": "warp-out", "ip_cidr": ["142.250.0.0/15"]},
                        {"outbound": "direct", "network": "udp,tcp"},
                    ]
                },
            }))
            allowlist.write_text("chatgpt.com\n*.openai.com\nchatgpt.com\n")

            result = subprocess.run(
                [
                    sys.executable,
                    str(SCRIPT),
                    "--config",
                    str(config),
                    "--allowlist",
                    str(allowlist),
                    "--dry-run",
                ],
                capture_output=True,
                text=True,
                check=True,
            )

            patched = json.loads(result.stdout)
            directs = [o for o in patched["outbounds"] if o["type"] == "direct" and "detour" not in o]
            self.assertTrue(all(o["bind_interface"] == "eth0" for o in directs))
            detoured = next(o for o in patched["outbounds"] if o["tag"] == "warp-IPv4-out")
            self.assertNotIn("bind_interface", detoured)

            rules = patched["route"]["rules"]
            self.assertIn("74.125.137.0/24", rules[1]["ip_cidr"])
            self.assertEqual(rules[1]["outbound"], "warp-out")
            self.assertEqual(rules[2], {
                "domain_suffix": ["chatgpt.com", "openai.com"],
                "outbound": "warp-out",
            })
            self.assertEqual(rules[3], {"outbound": "direct", "network": "udp,tcp"})


if __name__ == "__main__":
    unittest.main()
