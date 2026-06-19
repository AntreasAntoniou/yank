# Homebrew Cask for Ditto.
#
# Publish this from a tap repo (e.g. github.com/AntreasAntoniou/homebrew-tap)
# so users can:  brew install --cask antreasantoniou/tap/ditto
# Update `version` + `sha256` on each release (the CI prints the DMG sha256).
cask "ditto" do
  version "1.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/AntreasAntoniou/ditto/releases/download/v#{version}/Ditto-#{version}.dmg",
      verified: "github.com/AntreasAntoniou/ditto/"
  name "Ditto"
  desc "Fast, private clipboard manager with on-device semantic search"
  homepage "https://github.com/AntreasAntoniou/ditto"

  depends_on macos: ">= :ventura"

  app "Ditto.app"

  uninstall quit: "ai.axiotic.ditto"

  zap trash: [
    "~/Library/Application Support/Ditto",
    "~/Library/Preferences/ai.axiotic.ditto.plist",
  ]
end
