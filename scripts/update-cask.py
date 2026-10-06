#!/usr/bin/env python3
"""發版後更新 Homebrew tap（rocavence/homebrew-tap）的 Flione cask：版本與兩個 dmg 的 sha256 取自 GitHub 最新的 release。

用法：python3 scripts/update-cask.py          更新並 push
      python3 scripts/update-cask.py --dry-run  只印出 cask
tap 的本機位置：環境變數 FLIONE_TAP，預設 ~/Code/_app/homebrew-tap（沒有就 clone）
"""

import json
import os
import subprocess
import sys
from pathlib import Path

REPO = "rocavence/Flione-app"
TAP_REPO = "rocavence/homebrew-tap"
TAP = Path(os.environ.get("FLIONE_TAP", Path.home() / "Code/_app/homebrew-tap"))

CASK = """\
cask "flione" do
  arch arm: "AppleSilicon", intel: "Intel"

  version "{version}"
  sha256 arm:   "{arm}",
         intel: "{intel}"

  url "https://github.com/rocavence/Flione-app/releases/download/v#{{version}}/Flione-#{{version}}-#{{arch}}.dmg"
  name "Flione"
  desc "Music player for Jellyfin and YouTube Music"
  homepage "https://flione.rocavence.com/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :sonoma

  app "Flione.app"

  # Not notarized by Apple: remove the quarantine flag so the first launch isn't blocked.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{{{appdir}}}}/Flione.app"]
  end

  zap trash: [
    "~/Library/Application Support/com.rocavence.Flione",
    "~/Library/Caches/com.rocavence.Flione",
    "~/Library/HTTPStorages/com.rocavence.Flione",
    "~/Library/HTTPStorages/com.rocavence.Flione.binarycookies",
    "~/Library/Preferences/com.rocavence.Flione.plist",
    "~/Library/Saved Application State/com.rocavence.Flione.savedState",
    "~/Library/WebKit/com.rocavence.Flione",
  ]
end
"""


def run(*args: str, cwd: Path | None = None) -> str:
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True).stdout


def main() -> int:
    release = json.loads(run("gh", "api", f"repos/{REPO}/releases/latest"))
    version = release["tag_name"].removeprefix("v")
    digests = {}
    for asset in release["assets"]:
        for flavor in ("AppleSilicon", "Intel"):
            if asset["name"] == f"Flione-{version}-{flavor}.dmg":
                digests[flavor] = (asset.get("digest") or "").removeprefix("sha256:")
    if not all(digests.get(f) for f in ("AppleSilicon", "Intel")):
        print(f"v{version} 缺少 dmg 或 sha256：{digests}", file=sys.stderr)
        return 1

    cask = CASK.format(version=version, arm=digests["AppleSilicon"], intel=digests["Intel"])
    if "--dry-run" in sys.argv:
        sys.stdout.write(cask)
        return 0

    if not TAP.exists():
        run("gh", "repo", "clone", TAP_REPO, str(TAP))
    run("git", "pull", "--quiet", "--ff-only", cwd=TAP)
    path = TAP / "Casks/flione.rb"
    if path.exists() and path.read_text() == cask:
        print(f"cask 已經是 {version}")
        return 0
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(cask)
    run("git", "add", "Casks/flione.rb", cwd=TAP)
    run("git", "commit", "--quiet", "-m", f"flione {version}", cwd=TAP)
    run("git", "push", "--quiet", cwd=TAP)
    print(f"cask 更新為 {version}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
