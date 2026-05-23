import unittest
from pathlib import Path


REPO = Path(__file__).resolve().parents[1]


class DeployRouteScriptTest(unittest.TestCase):
    def test_deploy_route_script_mentions_required_steps(self):
        text = (REPO / "deploy-route.sh").read_text()
        self.assertIn("warp-allowlist.txt", text)
        self.assertIn("sync-singbox-route.py", text)
        self.assertIn("/etc/s-box/sb.json", text)
        self.assertIn("sing-box check", text)
        self.assertTrue("systemctl reload sing-box" in text or "systemctl restart sing-box" in text)


if __name__ == "__main__":
    unittest.main()
