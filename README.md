<div align="center">

# Unity Package Starter Kit

**Template for Unity Package Manager packages**<br>
A package project, an installer, test projects for several Unity versions,<br>
and CI that tests, signs and releases the package to OpenUPM

[![Use this template](https://img.shields.io/badge/Use_this_template-2ea44f?style=for-the-badge&logo=github)](https://github.com/Severnbli/unity-package-starter-kit/generate)

[![Unity 2021.3+](https://img.shields.io/badge/Unity-2021.3%2B-000000?logo=unity)](https://unity.com/)
[![OpenUPM](https://img.shields.io/badge/OpenUPM-signed_releases-3367d6)](https://openupm.com/)
[![Platforms](https://img.shields.io/badge/scripts-macOS_%7C_Linux_%7C_Windows-informational)](#scripts)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

[Layout](#layout) •
[Scripts](#scripts) •
[Create a package](#create-a-package) •
[Test projects](#test-projects) •
[CI](#ci) •
[Release](#release) •
[Differences from upstream](#differences-from-the-upstream-template)

</div>

> [!NOTE]
> This README describes the template. The init script replaces it with the package README skeleton from `Unity-Package/Assets/root/README.md`.

## Layout

| Path | Purpose |
|---|---|
| `Unity-Package/Assets/root/` | The package itself. Nothing outside this folder is shipped. |
| `Installer/` | Project that exports the installer `.unitypackage`, which adds the OpenUPM registry and pins the version. |
| `Unity-Tests/<version>/` | One empty project per tested Unity version, referencing the package as a local, testable dependency. |
| `commands/` | Init, version bump, consistency check, test project and "open all projects" scripts. |
| `.github/workflows/` | Test matrix and release pipeline (`*.yml-sample` until init). |
| `docs/` | Release and signing guides. |

---

## Scripts

Every script in `commands/` comes in two flavours with the same options:

| Platform | Run | Requirements |
|---|---|---|
| macOS, Linux | `*.sh` | bash (the macOS 3.2 one is enough), git, perl; `check-package.sh` also needs jq, python3 or node |
| Windows | `*.cmd` (runs the `*.ps1`) | git; the built-in Windows PowerShell 5.1 is enough, PowerShell 7 works too |

> [!TIP]
> The `.cmd` launcher works from cmd and PowerShell. It runs the `.ps1` of the same name with `-ExecutionPolicy Bypass` for that one process, so the default execution policy does not block it and no system setting changes. If your policy already allows scripts, run the `.ps1` directly.

Examples below show the macOS / Linux command first, then the Windows one.

---

## Create a package

### 1. Create the repository

Create a new repository from this template on GitHub and clone it.

### 2. Initialize

```bash
./commands/init.sh --package-id com.company.cool-package --package-name "Cool Package" --github-repository User/cool-package --installer-extra-path Editor
```

```bat
commands\init.cmd -PackageId "com.company.cool-package" -PackageName "Cool Package" -GitHubRepository "User/cool-package" -InstallerExtraPath "Editor"
```

| `.sh` option | `.ps1` parameter | Description |
|---|---|---|
| `--package-id` | `-PackageId` | Lowercase reverse-domain package name, e.g. `com.company.cool-package`. |
| `--package-name` | `-PackageName` | Display name, e.g. `Cool Package`. |
| `--github-repository` | `-GitHubRepository` | `owner/repo` slug for links, badges and release URLs. |
| `--root-namespace` | `-RootNamespace` | Optional C# root namespace. Defaults to `Company.CoolPackage`, derived from the id and name, because package ids may contain `-`. |
| `--installer-extra-path` | `-InstallerExtraPath` | Optional folder between `Assets/` and the installer folder, e.g. `Editor`. Prompted when omitted. |

The script replaces every placeholder in file contents and in file and folder names, enables `release.yml` and `test.yml`, and replaces this README with the package README. It refuses to run on an already initialized copy and never touches Unity's generated folders (`Library/`, `Temp/`, ...).

<details>
<summary>Placeholders</summary>

| Placeholder | Example |
|---|---|
| `YOUR_PACKAGE_ID` / `YOUR_PACKAGE_ID_LOWERCASE` | `com.company.cool-package` |
| `YOUR_PACKAGE_NAME` | `Cool Package` |
| `YOUR_PACKAGE_NAME_PASCAL` | `CoolPackage` |
| `YOUR_ROOT_NAMESPACE` | `Company.CoolPackage` |
| `YOUR_PACKAGE_NAME_INSTALLER` | `Editor/Cool Package Installer` |
| `YOUR_PACKAGE_NAME_INSTALLER_FILE` | `Cool-Package-Installer` |
| `YOUR_GITHUB_USERNAME_REPOSITORY` | `User/cool-package` |

</details>

### 3. Fill in `package.json`

In `Unity-Package/Assets/root/package.json`, set `description`, `keywords`, `unity` (minimum Unity version) and `dependencies`.

> [!TIP]
> For a dependency hosted on OpenUPM, also add its scope to `PackageIds` in `Installer/Assets/<installer>/Installer.Manifest.cs` and to the installer test fixtures.

### 4. Generate `.meta` files

> [!WARNING]
> Unity needs committed `.meta` files: without one, a file is left out of the `.unitypackage` and gets a new GUID on every import.

Open the projects once:

```bash
./commands/open-all-projects.sh
```

```bat
commands\open-all-projects.cmd
```

This opens `Installer` and `Unity-Package`, each in the editor version from its `ProjectSettings/ProjectVersion.txt`, found in the Unity Hub install folders (including a custom location set in Unity Hub).

<details>
<summary>Options</summary>

| `.sh` option | `.ps1` parameter | Description |
|---|---|---|
| `--with-tests` | `-WithTests` | Also open every test project in `Unity-Tests/`. |
| `--editors-path <dir>` | `-EditorsPath <dir>` | Look for editors in another folder first. |
| `--what-if` | `-WhatIf` | Print what would be opened. |
| `<project> ...` | `-Projects <project>,...` | Open only these projects, e.g. `Unity-Package`. |

</details>

Adding the projects to Unity Hub and opening them by hand works too.

### 5. Write the package

Follow the [Unity package layout](https://docs.unity3d.com/Manual/cus-layout.html):

```text
Unity-Package/Assets/root
├── package.json
├── README.md            identical copy of the root README.md
├── CHANGELOG.md         identical copy of the root CHANGELOG.md
├── LICENSE
├── Editor
│   └── YOUR_PACKAGE_ID.Editor.asmdef
├── Runtime
│   └── YOUR_PACKAGE_ID.Runtime.asmdef
├── Tests
│   ├── Editor
│   │   └── YOUR_PACKAGE_ID.Editor.Tests.asmdef
│   └── Runtime
│       └── YOUR_PACKAGE_ID.Tests.asmdef
├── Samples~
└── Documentation~
```

The test projects list the package under `testables`, so its tests run there without extra test assemblies.

### 6. Check before committing

```bash
./commands/check-package.sh
```

```bat
commands\check-package.cmd
```

The check needs no Unity license and runs first in CI. Over tracked files and new files git does not ignore, it verifies that:

- every JSON, manifest and `.asmdef` file parses,
- `package.json`, `Installer.cs` and both changelogs agree on the version,
- the package copies of `README.md` and `CHANGELOG.md` match the root files,
- every package asset has a `.meta` file, no `.meta` file is orphaned, and GUIDs are unique,
- the test workflow matrix lists exactly the projects in `Unity-Tests/`.

---

## Test projects

Each folder in `Unity-Tests/` is named after the Unity version it is tested with. The test project script adds and removes them and rewrites the `unityVersion` matrix in `test.yml` (`test.yml-sample` before init):

```bash
./commands/test-project.sh --list
./commands/test-project.sh --add 2023.2.22f1
./commands/test-project.sh --add 6000.0.58f2 --from 6000.3.1f1
./commands/test-project.sh --remove 2022.3.62f3
./commands/test-project.sh --sync
```

```bat
commands\test-project.cmd -List
commands\test-project.cmd -Add 2023.2.22f1
commands\test-project.cmd -Add 6000.0.58f2 -From 6000.3.1f1
commands\test-project.cmd -Remove 2022.3.62f3
commands\test-project.cmd -Sync
```

- `--add` copies the closest existing project (same major version first, without `Library/` and the lock file) and sets the new editor version. Open the new project once in that editor, let Unity upgrade it, and commit the result. Copying across major versions prints a warning: check `Packages/manifest.json` for packages that do not exist in the new version.
- `--sync` only rewrites the matrix, e.g. after renaming a folder by hand.
- The last test project cannot be removed, because the matrix cannot be empty.

---

## CI

### Secrets

Add them under **Settings > Secrets and variables > Actions**.

| Secret | Used for |
|---|---|
| `UNITY_EMAIL` | Unity activation |
| `UNITY_PASSWORD` | Unity activation |
| `UNITY_LICENSE` | Contents of `Unity_lic.ulf` (Windows: `C:/ProgramData/Unity/Unity_lic.ulf`, macOS: `/Library/Application Support/Unity/Unity_lic.ulf`, Linux: `~/.local/share/unity3d/Unity/Unity_lic.ulf`) |
| `UPM_ORG_ID` | Package signing |
| `UPM_SERVICE_ACCOUNT_KEY_ID` | Package signing |
| `UPM_SERVICE_ACCOUNT_KEY_SECRET` | Package signing |

> [!IMPORTANT]
> Signing is a hard gate: without the `UPM_*` secrets no release is created. [`docs/openupm-signing.md`](docs/openupm-signing.md) explains how to get them.

### Workflows

| Workflow | Runs | Does |
|---|---|---|
| **test** | On pull requests to `main` and `dev` that touch the package, the test projects or the installer | License-free checks first, then the package tests on every version in `Unity-Tests/` in EditMode, PlayMode and Standalone, and the installer tests in EditMode. Only the projects a PR touches are tested; a new push cancels the previous run. |
| **release** | On demand (**Actions > release > Run workflow**) | Fails if the version tag already exists, runs the full test matrix, builds the signed tarball and both `.unitypackage` files, attests them, and publishes the tag and GitHub Release in one step. |
| **test-unity-plugin** | Called by the two above | Runs one Unity test mode for one project. |

---

## Release

1. Bump the version:

   ```bash
   ./commands/bump-version.sh 1.0.1
   ```

   ```bat
   commands\bump-version.cmd -NewVersion "1.0.1"
   ```

   Prerelease versions (`1.1.0-preview.1`) and a preview mode (`--what-if` / `-WhatIf`) are supported. `--sync-docs to-package` / `-SyncDocs ToPackage` first copies the root `README.md` and `CHANGELOG.md` into the package; `to-root` / `ToRoot` copies the other way.
2. Add the changelog entry.
3. Merge, then run the release workflow.

[`docs/Deploy-OpenUPM.md`](docs/Deploy-OpenUPM.md) has the full checklist and the one-time OpenUPM setup.

---

## Differences from the upstream template

This repository is a fork of Ivan Murzak's [Unity-Package-Template](https://github.com/IvanMurzak/Unity-Package-Template).

| Area | Changes |
|---|---|
| Scripts | Every script exists as `.sh` and as `.ps1` with a `.cmd` launcher, running on the built-in Windows PowerShell 5.1; upstream has PowerShell scripts plus separate `open-all-projects-unix.sh` / `open-all-projects-windows.ps1`. New `check-package` and `test-project` scripts. `init` adds `--root-namespace`, the `YOUR_ROOT_NAMESPACE` and `YOUR_PACKAGE_NAME_PASCAL` placeholders, enables the workflows, swaps in the package README and refuses to run twice. `bump-version` adds prerelease versions, `--what-if` and `--sync-docs`. `open-all-projects` uses each project's editor version and Unity Hub's custom install folder. |
| CI | `test.yml-sample` replaces `test_pull_request.yml-sample`: a matrix built from `Unity-Tests/`, license-free checks first, only touched projects tested, older runs cancelled. `release.yml-sample` runs on demand instead of on every push to `main` and adds build provenance attestations. Actions are referenced by version tag, and the UPM CLI install script is not checked against a SHA-256. |
| Package and installer | C# namespaces use `YOUR_ROOT_NAMESPACE` instead of the package id, because ids may contain `-`. The installer adds only the package's own scope to the OpenUPM registry, not Ivan Murzak's and NuGet scopes; its define is `PACKAGE_INSTALLER_PROJECT` instead of `IVAN_MURZAK_INSTALLER_PROJECT`, and its test fixtures are reworked. `package.json` targets Unity `2021.3` instead of `2019.4` and links the documentation, changelog and license. The package skeleton drops `Editor/Gizmos` and `Editor/Scripts` and gains a README template. |
| Test projects | `2023.2.22f1` is removed; `2022.3.62f3` and `6000.3.1f1` remain. The projects list the package under `testables` instead of carrying sample test assemblies, and no longer commit `packages-lock.json` or the OpenUPM registry. |
| Repository | README and docs are rewritten; `Deploy-GitHub.md`, `Deploy-npmjs.md` and `Manual-Package-Rename.md` are removed. `FUNDING.yml` and the committed `.vscode/` folders are removed, IDE folders are ignored repository-wide, and `.gitattributes` keeps `.sh` on LF and `.cmd` on CRLF. The license holder changed. |
