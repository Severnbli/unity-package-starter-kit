<div align="center">

<h1>YOUR_PACKAGE_NAME</h1>

<p>
  <strong>One-line summary of what the package does</strong>
</p>

<p>
  <a href="https://openupm.com/packages/YOUR_PACKAGE_ID_LOWERCASE/">
    <img alt="OpenUPM" src="https://img.shields.io/npm/v/YOUR_PACKAGE_ID_LOWERCASE?label=openupm&registry_uri=https://package.openupm.com&color=blue" />
  </a>
  <a href="https://openupm.com/packages/YOUR_PACKAGE_ID_LOWERCASE/">
    <img alt="Downloads" src="https://img.shields.io/badge/dynamic/json?color=brightgreen&label=downloads&query=%24.downloads&suffix=%2Fmonth&url=https%3A%2F%2Fpackage.openupm.com%2Fdownloads%2Fpoint%2Flast-month%2FYOUR_PACKAGE_ID_LOWERCASE" />
  </a>
  <a href="https://unity.com/">
    <img alt="Unity 2021.3+" src="https://img.shields.io/badge/Unity-2021.3%2B-black?logo=unity" />
  </a>
  <a href="LICENSE">
    <img alt="MIT License" src="https://img.shields.io/badge/license-MIT-green" />
  </a>
</p>

<p>
  <a href="#quick-start">Quick start</a> •
  <a href="#installation">Installation</a> •
  <a href="#usage">Usage</a> •
  <a href="CHANGELOG.md">Changelog</a>
</p>

</div>

---

## Overview

Describe the problem the package solves and show the shortest example of it in action.

## Quick start

1. Install the package with [OpenUPM](#option-1--openupm-recommended):

   ```bash
   openupm add YOUR_PACKAGE_ID_LOWERCASE
   ```

2. Use it.

## Installation

Pick **one** variant. Do not mix them: the UPM package and the `.unitypackage` variants both provide assemblies named `YOUR_PACKAGE_ID.Runtime` / `.Editor`, so installing two of them causes duplicate assembly errors.

| Variant | Updates | Dependencies | Version tracking |
|---|---|---|---|
| [OpenUPM](#option-1--openupm-recommended) | Package Manager | automatic | manifest + lock file |
| [Signed tarball](#option-2--signed-tarball-tgz) | manual URL edit | automatic | manifest entry |
| [Installer `.unitypackage`](#option-3--installer-unitypackage) | one-shot manifest edit | automatic | manifest + lock file |
| [Standard `.unitypackage`](#option-4--standard-unitypackage-manual-versioning) | manual re-import | manual | **you** |

### Option 1 – OpenUPM (recommended)

The package is published on [OpenUPM](https://openupm.com/packages/YOUR_PACKAGE_ID_LOWERCASE/) as `YOUR_PACKAGE_ID_LOWERCASE`.

1. Install the [OpenUPM CLI](https://github.com/openupm/openupm-cli#installation) (requires Node.js):

   ```bash
   npm install -g openupm-cli
   ```

2. Open a terminal in your Unity project folder (the one containing `Assets/` and `Packages/`) and run:

   ```bash
   openupm add YOUR_PACKAGE_ID_LOWERCASE
   ```

3. Switch back to Unity. The package resolves and compiles.

> [!TIP]
> `openupm add` handles the scoped registry, dependency resolution and `manifest.json` changes for you. You can also add the package from **Window > Package Manager** if the OpenUPM registry is already configured.

<details>
<summary><strong>Manual installation (without the CLI)</strong></summary>

<br/>

Add the scoped registry and the dependency to `Packages/manifest.json`:

```json
{
  "scopedRegistries": [
    {
      "name": "OpenUPM",
      "url": "https://package.openupm.com",
      "scopes": [
        "YOUR_PACKAGE_ID_LOWERCASE"
      ]
    }
  ],
  "dependencies": {
    "YOUR_PACKAGE_ID_LOWERCASE": "1.0.0"
  }
}
```

Then let Unity refresh the project. Replace the version with the latest one shown on the badge above.

</details>

### Option 2 – Signed tarball (`.tgz`)

Every release ships a signed UPM tarball, `tarball-YOUR_PACKAGE_ID_LOWERCASE-<version>.tgz`, which is the same artifact OpenUPM consumes. Add it as a file dependency:

```json
{
  "dependencies": {
    "YOUR_PACKAGE_ID_LOWERCASE": "https://github.com/YOUR_GITHUB_USERNAME_REPOSITORY/releases/download/<version>/tarball-YOUR_PACKAGE_ID_LOWERCASE-<version>.tgz"
  }
}
```

Unity resolves the package's own dependencies from the tarball. Packages installed from a URL are not updated automatically – editing the URL or version by hand is the update. It also works for offline machines: download the file once and reference it with a `file:` path. The `.attestation.p7m` signature inside the archive is what OpenUPM verifies; Unity itself does not.

### Option 3 – Installer `.unitypackage`

Download `installer-YOUR_PACKAGE_ID_LOWERCASE-<version>.unitypackage` from the release and import it (**Assets > Import Package > Custom Package**). It contains only an editor script under `Assets/YOUR_PACKAGE_NAME_INSTALLER/`, which on the next domain reload:

- registers the OpenUPM scoped registry in `Packages/manifest.json`, and
- pins `YOUR_PACKAGE_ID_LOWERCASE` to the installer's version.

Package Manager then downloads and manages the real package, so dependencies resolve automatically and updates work as in Option 1. The installer never downgrades: it only writes the version when the installer's version is newer than the one already pinned.

### Option 4 – Standard `.unitypackage` (manual versioning)

Download `YOUR_PACKAGE_ID_LOWERCASE-<version>.unitypackage` from the release and import it. Sources land in `Assets/Plugins/YOUR_PACKAGE_NAME_PASCAL/`. Committed `.meta` GUIDs are preserved, so script references survive a re-import and a later upgrade.

This variant bypasses Package Manager, so **versioning is manual**:

- No `package.json` is included, so Unity does not know which version is installed and Package Manager cannot list, update or uninstall it. Record the version yourself – keep the versioned release file or note it in your changelog.
- To update, delete `Assets/Plugins/YOUR_PACKAGE_NAME_PASCAL/` and import the newer `.unitypackage`. There are no partial upgrades, and stale files are not cleaned up.
- Install the package's dependencies yourself. Nothing resolves them for you.

## Requirements

| Requirement | Version |
|---|---|
| Unity | 2021.3 or newer |

## Usage

Document the public API here.

## License

[MIT](LICENSE) © Usevalad Buben
