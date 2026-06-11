# Updates Manager Plugin for KOReader

As the number of patches and plugins for KOReader continues to grow, keeping track of updates has become increasingly difficult. Manually checking each repository for updates is time-consuming and error-prone. That's why I've created **Updates Manager** - a plugin that automates checking for and installing updates from multiple GitHub repositories.

## What It Does

The plugin automatically:
- Scans multiple patch and plugin repositories for updates
- Compares installed versions with the latest available versions
- Shows you which patches/plugins have updates available
- Allows you to selectively update what you want
- Handles MD5 verification for patch integrity

## Important Warnings ⚠️

**This is a complex system and requires thorough testing. Please:**
- **Backup your plugins and patches** before using this plugin
- Test on a device you can easily restore if needed
- Report any bugs or issues you encounter

**For patches:** When you update a patch, any local modifications you made will be **completely overwritten**. The plugin creates a backup (`.old` file), but if you've customized patches, consider documenting your changes first.

## How to Use

The plugin comes with **default repositories** already configured, so you can start using it right away without any configuration!

### For Patches

1. Navigate to **Updates Manager** → **Patches** → **Check for Updates**
2. The plugin will scan all default patch repositories
3. Select which patches to update
4. Click **Update Selected**

**Want to add your own patch repository?**

If you have patches in a repository that's not in the default list, you can:
- **Option 1:** Create a pull request to add it to the default list (see below)
- **Option 2:** Manually add it to `KOReader/settings/updatesmanager_config.json`:

```json
{
  "patches": [
    {
      "owner": "username",
      "repo": "KOReader.patches",
      "branch": "main",
      "path": "",
      "description": "My patches collection"
    }
  ]
}
```

See the [README](https://github.com/advokatb/updatesmanager.koplugin#example-configuration-patches) for more configuration examples.

### For Plugins

1. Navigate to **Updates Manager** → **Plugins** → **Check for Updates**
2. The plugin will scan all default plugin repositories
3. Select which plugins to update
4. Click **Update Selected**

**Important for plugin authors:**
- Your plugin's `_meta.lua` file **must** have a `version` field
- Create GitHub Releases with version tags (e.g., `v1.0.0` or `1.0.0`)
- The release tag should match the version in `_meta.lua`

**Note:** If your plugin doesn't have a version in `_meta.lua`, the plugin will always show an update available (even if you're on the latest release). See [Version Management](https://github.com/advokatb/updatesmanager.koplugin#version-management) and [Adding Version to Your Plugin](https://github.com/advokatb/updatesmanager.koplugin#adding-version-to-plugin) for details.

**Want to add your own plugin repository?**

If you have a plugin that's not in the default list, you can:
- **Option 1:** Create a pull request to add it to the default list (see below)
- **Option 2:** Manually add it to `KOReader/settings/updatesmanager_config.json`:


## Adding Your Repository

Want to add your patches or plugins to the default list so all users can access them?

1. Fork the [Updates Manager repository](https://github.com/advokatb/updatesmanager.koplugin)
2. Add your repository to `updatesmanager_config.lua` in the appropriate table (`DEFAULT_PATCH_REPOS` or `DEFAULT_PLUGIN_REPOS`)
3. Create a pull request with a description of your repository
4. Your PR will be reviewed and merged

See the [README section](https://github.com/advokatb/updatesmanager.koplugin#adding-patch-repository) for more details.

## Features

- Multi-repository support
- Selective updates (choose what to update)
- Smart caching to reduce API calls
- Rate limit handling
- MD5 verification for patches
- Patch descriptions (from `updates.json`, comments, or local edits)
- Plugin version comparison
- Ignore list for modified patches

## Known Limitations & Testing Status

- The `updates.json` workflow scenario (for automatic MD5 hash generation) hasn't been fully tested yet. If you use it, please report any issues.
- The plugin may contain bugs - **please report them** so we can improve it!
- This is a complex system that interacts with multiple repositories and APIs - thorough testing is needed

## Documentation

For detailed documentation, configuration examples, troubleshooting, and more, see the [full README](https://github.com/advokatb/updatesmanager.koplugin).

## Installation

1. Download from the [Releases page](https://github.com/advokatb/updatesmanager.koplugin/releases)
2. Extract to your KOReader `plugins` directory
3. Restart KOReader

## Feedback Welcome

This is a work in progress. If you find bugs, have suggestions, or want to contribute, please:
- Open an issue on GitHub
- Submit a pull request
- Share your feedback here

Thanks for testing, and remember to **backup your data**!

---

**Repository:** https://github.com/advokatb/updatesmanager.koplugin

