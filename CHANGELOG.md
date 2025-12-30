# Changelog

## [1.3.3] - 2025-12-23

### Fixed
- **Subprocess stability**: Fixed "unwrapped dismissableRunInSubprocess()" warnings by ensuring `processing_msg` widget exists before using it as `trap_widget`
  - Added checks to create `processing_msg` if it doesn't exist before all `dismissableRunInSubprocess` calls
  - Prevents fallback to blocking in-process execution mode

### Changed
- Updated plugin and patch repository lists in default configuration

## [1.3.2] - 2025-12-23

- Revert Install Plugins feature till I find a proper solution to avoid crashes

## [1.3.1] - 2025-12-22

### Changed
- **Install New Plugins UI**:
  - Added pagination to the installable plugins list to avoid huge dialogs and out-of-screen content.
  - Limit 10 plugins per page with page indicator in the title (e.g. `Page 1/3`).
  - Navigation buttons (**Previous** / **Next**) to move between pages.
  - Selections are preserved when switching pages so multiple plugins can be installed in one go.

### Fixed
- Improved stability of the **Install New Plugins** dialog on Android and desktop:
  - Avoid creating an excessively large number of widgets at once.
  - Reduced risk of ANR / “isn't responding” popups and layout issues on macOS.

## [1.3.0] - 2025-12-17

### Added
- **Install New Plugins**: Install plugins from the active `DEFAULT_PLUGIN_REPOS` list (GitHub Releases assets).
  - Shows only repositories that are not currently installed.
  - Installs by downloading the latest release ZIP asset and extracting it to `KOReader/plugins/`.
  - Validates ZIP structure to avoid polluting the plugins directory (expects a single `*.koplugin` folder at ZIP root).

## [1.2.1] - 2025-12-17

### Changed
- Re-enabled `agaragou/illustrations.koplugin` in default plugin repositories.

## [1.2.0] - 2025-12-XX

### Added
- **Asset Pattern Filtering**: Added support for `asset_pattern` field in repository configuration to filter release assets by filename pattern
  - Useful for repositories that release multiple platform-specific files (AppImages, RPMs, DEBs, etc.) alongside plugin ZIPs
  - Supports glob-style patterns (e.g., `*.koplugin.zip`) which are automatically converted to Lua patterns
  - Example: `readest/readest` repository can now be configured with `"asset_pattern": "*.koplugin.zip"` to download only the plugin file
  - If `asset_pattern` is not specified, defaults to matching any `.zip` file (backward compatible)
- Added `readest/readest` to default plugin repositories (with `asset_pattern` configured).

### Changed
- Improved plugin name display in update results: now shows full plugin name (`fullname` from `_meta.lua`) instead of technical name (e.g., "Updates Manager" instead of "updatesmanager").

## [1.1.0] - 2025-12-07

### Added
- **GitHub Personal Access Token Support**: Added support for GitHub Personal Access Token to avoid API rate limits
  - Without token: 60 requests/hour (shared limit for all unauthenticated requests)
  - With token: 5,000 requests/hour (personal limit)
  - Token configuration file: `KOReader/settings/updatesmanager_github_token.txt`
  - Template file is automatically created on first plugin launch with detailed instructions
  - Token is automatically used for all GitHub API requests when configured
  - Only requires `public_repo` scope (read-only access to public repositories)
- Added `de3sw2aq1/koreader-patches` to default patch repositories (patches in `patches/` subfolder).
- Added `0zd3m1r/KOReader.patches` to default patch repositories.
- Added `TelegramDownloader.koplugin` back to active plugin repositories (moved from commented-out list).

## [1.0.7] - 2025-12-02

### Fixed
- Fixed crash when comparing plugin versions: handle cases where version in `_meta.lua` is stored as a number instead of a string (e.g., `version = 1.0` instead of `version = "1.0.0"`).

### Added
- Added `reuerendo/koreader-patches` to default patch repositories.

## [1.0.6] - 2025-12-02

### Added
- Added `whatsnewsisyphus/koreader-patches` to default patch repositories.
- Added `agaragou/illustrations.koplugin` to default plugin repositories.
- Added `omer-faruq/tbrplanner.koplugin` to default plugin repositories.
- Added `omer-faruq/nonogram.koplugin` to default plugin repositories.

## [1.0.5] - 2025-11-18

### Added
- Added `prashanthglen/kojustifystatusbar` to default patch repositories (Justify status bar patch).
- Added `clarainna/KOReader-Patches` to default patch repositories.

### Changed
- Commented out plugin repositories without proper releases: `imagebookmarks.koplugin`, `weather.koplugin`, `koreader-booknotes-plugin`, `koreader-xray-plugin`, `crashlog.koplugin`, `multiline-toc-koreader`, `TelegramDownloader.koplugin`.
- Reorganized `config.lua`: moved all commented-out repositories to the end of the list for better maintainability.
- Updated README: removed commented-out repositories from the supported repositories list.

## [1.0.4] - 2025-11-18

### Fixed
- Prevented the changelog popup from crashing or showing raw `<img …>` tags by hardening markdown sanitizing (safer pattern matching and full removal of markdown/HTML images).

## [1.0.3] - 2025-11-17

### Added
- Included `AnnotationSync.koplugin` in the default plugin repository list. ([#5](https://github.com/advokatb/updatesmanager.koplugin/pull/5))

### Fixed
- Prevented the **View Settings** screen from crashing by ensuring the dialog has the imports it needs before rendering descriptions. ([#7](https://github.com/advokatb/updatesmanager.koplugin/pull/7))
- Corrected the README link to the Releases page so users land on the right download location. ([#6](https://github.com/advokatb/updatesmanager.koplugin/pull/6))

## [1.0.2] - 2025-11-17

### Added
- Added an inline **changelog** label and icon for every plugin update entry so users can open the release notes inside KOReader with markdown styling (bold headings, preserved lists, stripped links). ([#4](https://github.com/advokatb/updatesmanager.koplugin/issues/4))


## [1.0.1] - 2025-11-13

### Changed
- Removed some of `loeffner/KOReader.patches` from the default patch repository list. ([#3](https://github.com/advokatb/updatesmanager.koplugin/pull/3))
- Added `kristianpennacchia/WordReference.koplugin` to the default plugin repositories. ([#2](https://github.com/advokatb/updatesmanager.koplugin/pull/2))

## [1.0.0] - 2025-11-12

### Added

#### Core Features
- **Multi-Repository Patch Updates**: Automatically check for updates to installed patches from multiple GitHub repositories simultaneously
- **Multi-Repository Plugin Updates**: Check for plugin updates from multiple GitHub repositories
- **Selective Updates**: Choose which patches/plugins to update with checkboxes
- **Smart Caching**: Repository data is cached to reduce API calls and improve performance
- **Rate Limit Handling**: Automatically handles GitHub API rate limits with intelligent retry logic
- **Progress Display**: Real-time progress updates during update checks and installations
- **Safe Installation**: Backs up existing patches and plugins before updating (`.old` files)
- **MD5 Verification**: Validates patch integrity using MD5 checksums

#### Patch Management
- **Patch Descriptions**: 
  - Automatic extraction from `updates.json` files in repositories
  - Fallback to parsing comments from patch files
  - Local editing and customization of descriptions
  - Preview in update lists and detailed view
- **Patch Information**: View detailed information about patches including:
  - Author and repository
  - Description (from multiple sources)
  - File size and MD5 hash
  - Repository URL
- **Ignore List**: Ability to ignore specific patches from update checks via `updatesmanager_ignored_patches.txt`
- **Patch Details**: Long-press on patches to view detailed information

#### Plugin Management
- **Plugin Version Comparison**: Automatic semantic version comparison for plugins
- **Plugin Information**: View detailed information about plugins including:
  - Version (installed vs. available)
  - Release notes
  - Repository URL
- **Default Plugin Filtering**: Default KOReader plugins are automatically hidden from the installed plugins list
- **Plugin Details**: Long-press on plugins to view detailed information

#### User Interface
- **Menu Structure**: Organized into Patches, Plugins, and Settings sections
- **Force Refresh**: Option to bypass cache and fetch fresh data
- **Update Results**: Detailed display of successful and failed updates
- **Installed Patches List**: View all installed patches with descriptions
- **Installed Plugins List**: View all installed plugins with versions
- **Edit Descriptions**: Ability to edit patch descriptions locally
- **Progress Monitoring**: File-based progress communication for non-blocking operations

#### Configuration
- **Default Repositories**: Pre-configured list of popular patch and plugin repositories
- **Custom Repository Support**: Add custom repositories via configuration file
- **Repository Settings Menu**: View configuration file location and repository counts
- **Configuration File**: `KOReader/settings/updatesmanager_config.json`

#### Technical Features
- **Network Management**: Automatic Wi-Fi connection handling
- **Error Handling**: Graceful handling of network errors and API limits
- **Subprocess Support**: Uses `Trapper:dismissableRunInSubprocess` for non-blocking operations
- **Fallback Mode**: Handles blocking mode gracefully with UI updates
- **File Locations**:
  - Configuration: `KOReader/settings/updatesmanager_config.json`
  - Cache: `KOReader/settings/updatesmanager_cache/`
  - Local Descriptions: `KOReader/settings/updatesmanager_patch_descriptions.json`
  - Ignored Patches: `KOReader/settings/updatesmanager_ignored_patches.txt`

### Default Repositories

<details>
<summary><strong>Patch Repositories (7)</strong></summary>

- joshuacant/KOReader.patches
- angelsangita/Koreader-Patches
- SeriousHornet/KOReader.patches
- sebdelsol/KOReader.patches
- zenixlabs/koreader-frankenpatches-public
- omer-faruq/koreader-user-patches
- advokatb/KOReader-Patches

</details>

<details>
<summary><strong>Plugin Repositories (23)</strong></summary>

- loeffner/WeatherLockscreen
- advokatb/readingstreak.koplugin
- advokatb/updatesmanager.koplugin
- bozo22/imagebookmarks.koplugin
- roygbyte/weather.koplugin
- marinov752/emailtokoreader.koplugin
- omer-faruq/memobook.koplugin
- 0zd3m1r/koreader-booknotes-plugin
- omer-faruq/rssreader.koplugin
- 0zd3m1r/koreader-xray-plugin
- Billiam/crashlog.koplugin
- kodermike/airplanemode.koplugin
- kristianpennacchia/zzz-readermenuredesign.koplugin
- kristianpennacchia/WordReference.koplugin
- patelneeraj/filebrowserplus.koplugin
- omer-faruq/webbrowser.koplugin
- Billiam/hardcoverapp.koplugin
- omer-faruq/assistant.koplugin
- monk-blade/multiline-toc-koreader
- 0xmiki/telegramhighlights.koplugin
- Evgeniy-94/TelegramDownloader.koplugin
- joshuacant/ProjectTitle
- JoeBumm/Koreader-Menu-customizer

</details>

### Notes

- Based on `2-update-patches.lua` by sebdelsol
- Inspired by the KOReader patch and plugin ecosystem
- This is the initial release - the system is complex and requires thorough testing

