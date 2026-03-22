---
name: release-desktop
description: Release the NamingPaper macOS desktop app - build, sign, create DMG, generate appcast, and publish GitHub release.
metadata:
  author: namingpaper
  version: "1.0"
---

# Desktop App Release Procedure

Follow these steps to release a new version of the NamingPaper macOS desktop app. The user should provide the version number (X.Y.Z).

## Pre-flight

1. **Confirm version number** with the user.
2. **Ask whether this is a stable or prerelease**.
3. **Bump version** in the Xcode project:
   - Update `MARKETING_VERSION` to `X.Y.Z` in `macos/NamingPaper/NamingPaper.xcodeproj/project.pbxproj`
   - Increment `CURRENT_PROJECT_VERSION` (build number) in the same file
   - Both the Debug and Release configurations must be updated.

4. **Verify version consistency** across all files before building:
   - `MARKETING_VERSION` in `project.pbxproj` (Debug and Release) → must be `X.Y.Z`
   - `CURRENT_PROJECT_VERSION` in `project.pbxproj` (Debug and Release) → must be incremented
   - `sparkle:shortVersionString` in `appcast.xml` will be set automatically by `generate_appcast`
   - Run a quick check:

     ```bash
     grep -n "MARKETING_VERSION" macos/NamingPaper/NamingPaper.xcodeproj/project.pbxproj
     grep -n "CURRENT_PROJECT_VERSION" macos/NamingPaper/NamingPaper.xcodeproj/project.pbxproj
     ```

   - **Stop and fix** if any values are inconsistent before proceeding.

## Build

1. **Remind the user** to build the archive in Xcode:
   - Product → Archive
   - Organizer → Distribute App → Custom → Copy App → export to a known folder (e.g., Desktop)
2. **Wait for the user** to confirm the export path before proceeding.

## Package

1. **Find the exported `.app`**:

   ```bash
   find ~ -maxdepth 4 -name "NamingPaper.app" -not -path "*/DerivedData/*" -not -path "*/Archives/*" -newer /tmp -print 2>/dev/null
   ```

   Confirm with the user if multiple results are found.

2. **Create the ZIP** (for Sparkle auto-update):

   ```bash
   mkdir -p ~/sparkle-releases
   ditto -c -k --sequesterRsrc --keepParent /path/to/NamingPaper.app ~/sparkle-releases/NamingPaper.zip
   ```

3. **Create the DMG** (for manual download) with Applications symlink:

   ```bash
   rm -rf /tmp/dmg-staging && mkdir -p /tmp/dmg-staging
   cp -R /path/to/NamingPaper.app /tmp/dmg-staging/
   ln -s /Applications /tmp/dmg-staging/Applications
   hdiutil create -volname "NamingPaper" -srcfolder /tmp/dmg-staging -ov -format UDZO ~/sparkle-releases/NamingPaper-vX.Y.Z.dmg
   ```

4. **Generate appcast.xml** (Sparkle update feed):

   ```bash
   # generate_appcast reads the EdDSA private key from Keychain automatically
   # Find the tool:
   find ~/Library/Developer/Xcode/DerivedData -name "generate_appcast" -type f 2>/dev/null | head -1
   # Move the DMG out first — generate_appcast errors on duplicate bundle versions
   mv ~/sparkle-releases/NamingPaper-vX.Y.Z.dmg /tmp/
   # Run it (ZIP only):
   /path/to/generate_appcast ~/sparkle-releases/
   # Move the DMG back:
   mv /tmp/NamingPaper-vX.Y.Z.dmg ~/sparkle-releases/
   ```

   Verify the generated `appcast.xml` contains the correct version and EdDSA signature.

## Publish

1. **Create or update GitHub release** on `DanTsai0903/namingpaper-desktop`:
    - If a pre-release already exists for this tag:

      ```bash
      # Delete old assets and upload new ones
      gh release delete-asset vX.Y.Z NamingPaper.zip --repo DanTsai0903/namingpaper-desktop --yes 2>/dev/null
      gh release delete-asset vX.Y.Z appcast.xml --repo DanTsai0903/namingpaper-desktop --yes 2>/dev/null
      gh release delete-asset vX.Y.Z NamingPaper-vX.Y.Z.dmg --repo DanTsai0903/namingpaper-desktop --yes 2>/dev/null
      gh release upload vX.Y.Z ~/sparkle-releases/NamingPaper.zip ~/sparkle-releases/appcast.xml ~/sparkle-releases/NamingPaper-vX.Y.Z.dmg --repo DanTsai0903/namingpaper-desktop
      # Promote to latest if stable
      gh release edit vX.Y.Z --repo DanTsai0903/namingpaper-desktop --prerelease=false --latest
      ```

    - If creating a new release:

      ```bash
      gh release create vX.Y.Z \
        ~/sparkle-releases/NamingPaper.zip \
        ~/sparkle-releases/appcast.xml \
        ~/sparkle-releases/NamingPaper-vX.Y.Z.dmg \
        --repo DanTsai0903/namingpaper-desktop \
        --title "vX.Y.Z" \
        --generate-notes \
        --prerelease  # omit for stable release
      ```

2. **Verify** the release:

    ```bash
    gh release view vX.Y.Z --repo DanTsai0903/namingpaper-desktop
    ```

    Confirm all 3 assets are present: `NamingPaper.zip`, `appcast.xml`, `NamingPaper-vX.Y.Z.dmg`.

## Important

- Always confirm the version number with the user before starting.
- Always update both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in the Xcode project.
- Use `ditto` (not `zip`) to create the ZIP — it preserves macOS metadata and code signatures.
- The `SUFeedURL` in Info.plist points to `https://github.com/DanTsai0903/namingpaper-desktop/~/sparkle-releaseslatest/download/appcast.xml` — only the **latest** (non-prerelease) GitHub release is picked up by Sparkle.
- The EdDSA private key is stored in the macOS Keychain under "Sparkle EdDSA Key".
- Clean up staging files after release: `rm -rf /tmp/dmg-staging /tmp/NamingPaper-rw.dmg`
