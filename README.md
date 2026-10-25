# Unity Package Starter Kit

Template for Unity Package Manager packages: a package project, an installer, test projects for several Unity versions, and CI that tests, signs and releases the package to OpenUPM.

> [!NOTE]
> This README describes the template. The init script replaces it with the package README skeleton from `Unity-Package/Assets/root/README.md`.

## Layout

| Path | Purpose |
|---|---|
| `Unity-Package/Assets/root/` | The package itself. Everything outside this folder is not shipped. |
| `Installer/` | Project that exports the installer `.unitypackage` (adds the OpenUPM registry and pins the version). |
| `Unity-Tests/<version>/` | Empty projects that reference the package as a local, testable dependency, one per tested Unity version. |
| `commands/` | Init, version bump, consistency check, test project and "open all projects" scripts. |
| `.github/workflows/` | Test matrix and release pipeline (`*.yml-sample` until init). |
| `docs/` | Release and signing guides. |

## Create a package

### 1. Create the repository

Create a new repository from this template on GitHub and clone it.

Every script in `commands/` comes twice, with the same options:

| Platform | Scripts | Requirements |
|---|---|---|
| macOS, Linux | `*.sh` | bash (the macOS 3.2 one is enough), git, perl; `check-package.sh` also needs one of jq, python3 or node |
| Windows | `*.cmd`, running `*.ps1` | git; nothing else: the built-in Windows PowerShell 5.1 is enough (PowerShell 7 works too) |

On Windows run the `.cmd` launcher from cmd or PowerShell. It starts the `.ps1` script of the same name with `-ExecutionPolicy Bypass` for that one process, so Windows' default execution policy does not block it and no system setting changes. If your execution policy already allows scripts, you can also run the `.ps1` directly.

The examples below show the macOS / Linux command first and the Windows one below it.

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
| `--github-repository` | `-GitHubRepository` | `owner/repo` slug, used for links, badges and release URLs. |
| `--root-namespace` | `-RootNamespace` | Optional C# root namespace. Defaults to `Company.CoolPackage`, derived from the id and name, because package ids may contain `-`. |
| `--installer-extra-path` | `-InstallerExtraPath` | Optional folder between `Assets/` and the installer folder, e.g. `Editor`. Prompted when omitted. |

The script refuses to run on an already initialized copy and never touches Unity's generated folders (`Library/`, `Temp/`, ...).

The script:

- replaces every placeholder in file contents and in file and folder names,
- enables `release.yml` and `test.yml`,
- replaces this README with the package README.

| Placeholder | Example |
|---|---|
| `YOUR_PACKAGE_ID` / `YOUR_PACKAGE_ID_LOWERCASE` | `com.company.cool-package` |
| `YOUR_PACKAGE_NAME` | `Cool Package` |
| `YOUR_PACKAGE_NAME_PASCAL` | `CoolPackage` |
| `YOUR_ROOT_NAMESPACE` | `Company.CoolPackage` |
| `YOUR_PACKAGE_NAME_INSTALLER` | `Editor/Cool Package Installer` |
| `YOUR_PACKAGE_NAME_INSTALLER_FILE` | `Cool-Package-Installer` |
| `YOUR_GITHUB_USERNAME_REPOSITORY` | `User/cool-package` |

### 3. Fill in `package.json`

Open `Unity-Package/Assets/root/package.json` and set `description`, `keywords`, `unity` (minimum Unity version) and `dependencies`.

If a dependency is hosted on OpenUPM, add its scope to `PackageIds` in `Installer/Assets/<installer>/Installer.Manifest.cs` and to the installer test fixtures.

### 4. Generate `.meta` files

Unity needs committed `.meta` files: a missing one drops the file from the `.unitypackage` and gives it a new GUID on every import. Open the projects once:

```bash
./commands/open-all-projects.sh
```

```bat
commands\open-all-projects.cmd
```

This opens `Installer` and `Unity-Package`, each with the editor version in its `ProjectSettings/ProjectVersion.txt`, from the Unity Hub install folders (including a custom location set in Unity Hub). Options:

| `.sh` option | `.ps1` parameter | Description |
|---|---|---|
| `--with-tests` | `-WithTests` | Also open every test project in `Unity-Tests/`. |
| `--editors-path <dir>` | `-EditorsPath <dir>` | Look for editors in another folder first. |
| `--what-if` | `-WhatIf` | Print what would be opened. |
| `<project> ...` | `-Projects <project>,...` | Open only these projects, e.g. `Unity-Package`. |

You can also add the projects to Unity Hub and open them by hand.

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

The script needs no Unity license and runs first in CI. It looks at tracked files and at new files git does not ignore, and checks that:

- every JSON, manifest and `.asmdef` file parses,
- `package.json`, `Installer.cs` and both changelogs agree on the version,
- the package copies of `README.md` and `CHANGELOG.md` match the root files,
- every package asset has a `.meta` file, no `.meta` file is orphaned, and GUIDs are unique,
- the test workflow matrix lists exactly the projects in `Unity-Tests/`.

## Test projects

Each folder in `Unity-Tests/` is named after the Unity version it is tested with. Add or remove one with the test project script; it also rewrites the `unityVersion` matrix in `test.yml` (or `test.yml-sample` before init):

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

`--add` copies the closest existing project (same major version first, without `Library/` and the lock file) and sets the new editor version. Open the new project once in that editor, let Unity upgrade it, and commit the result. Copying across major versions prints a warning: check `Packages/manifest.json` for packages that do not exist in the new version. `--sync` only rewrites the matrix, e.g. after renaming a folder by hand. The last test project cannot be removed, because the matrix cannot be empty.

## CI

### Secrets

Add them under **Settings > Secrets and variables > Actions**.

| Name | Kind | Used for |
|---|---|---|
| `UNITY_EMAIL` | secret | Unity activation |
| `UNITY_PASSWORD` | secret | Unity activation |
| `UNITY_LICENSE` | secret | Contents of `Unity_lic.ulf` (Windows: `C:/ProgramData/Unity/Unity_lic.ulf`, macOS: `/Library/Application Support/Unity/Unity_lic.ulf`, Linux: `~/.local/share/unity3d/Unity/Unity_lic.ulf`) |
| `UPM_ORG_ID` | secret | Package signing |
| `UPM_SERVICE_ACCOUNT_KEY_ID` | secret | Package signing |
| `UPM_SERVICE_ACCOUNT_KEY_SECRET` | secret | Package signing |

Signing is a hard gate: without the `UPM_*` values no release is created. [`docs/openupm-signing.md`](docs/openupm-signing.md) explains how to get them.

### Workflows

- **test** runs on pull requests to `main` and `dev` that touch the package, the test projects or the installer. The license-free checks run first; then the package tests run on every Unity version in `Unity-Tests/` in EditMode, PlayMode and Standalone, and the installer tests run in EditMode. Only the projects a PR touches are tested, and a new push cancels the previous run.
- **release** runs only on demand (**Actions > release > Run workflow**). It fails if the version tag already exists, runs the full test matrix, builds the signed tarball and both `.unitypackage` files, attests them and publishes the tag and GitHub Release in one step.
- **test-unity-plugin** is the reusable job that runs one Unity test mode for one project.

To test another Unity version, use the [test project script](#test-projects).

## Release

```bash
./commands/bump-version.sh 1.0.1
```

```bat
commands\bump-version.cmd -NewVersion "1.0.1"
```

Both accept prerelease versions (`1.1.0-preview.1`) and a preview mode (`--what-if` / `-WhatIf`). Add `--sync-docs to-package` / `-SyncDocs ToPackage` to copy the root `README.md` and `CHANGELOG.md` into the package first, or `to-root` / `ToRoot` for the other direction.

Then add the changelog entry, merge and run the release workflow. See [`docs/Deploy-OpenUPM.md`](docs/Deploy-OpenUPM.md) for the full checklist and the one-time OpenUPM setup.

## Differences from the upstream template

This repository is a fork of Ivan Murzak's [Unity-Package-Template](https://github.com/IvanMurzak/Unity-Package-Template). Compared with it:

**Scripts**

- Every script exists for macOS / Linux (`.sh`) and Windows (`.ps1` with a `.cmd` launcher); upstream ships PowerShell scripts plus separate `open-all-projects-unix.sh` / `open-all-projects-windows.ps1`. The PowerShell scripts run on the built-in Windows PowerShell 5.1.
- `init` also takes `--root-namespace`, adds the `YOUR_ROOT_NAMESPACE` and `YOUR_PACKAGE_NAME_PASCAL` placeholders, enables the workflows, swaps in the package README and refuses to run twice.
- New `check-package` (license-free consistency checks) and `test-project` (add, remove and sync test projects) scripts.
- `bump-version` also accepts prerelease versions, `--what-if` and `--sync-docs`; `open-all-projects` picks each project's editor version and reads Unity Hub's custom install folder.

**CI**

- `test_pull_request.yml-sample` is replaced by `test.yml-sample`: a matrix built from the folders in `Unity-Tests/`, license-free checks first, only the touched projects tested, and older runs cancelled.
- `release.yml-sample` runs only on demand instead of on every push to `main`, and it adds build provenance attestations to the release files.
- Actions are referenced by version tag, and the UPM CLI install script is not checked against a SHA-256.

**Package and installer**

- C# namespaces use `YOUR_ROOT_NAMESPACE` instead of the package id, because ids may contain `-`.
- The installer adds only the package's own scope to the OpenUPM registry instead of Ivan Murzak's and NuGet scopes; its define is `PACKAGE_INSTALLER_PROJECT` instead of `IVAN_MURZAK_INSTALLER_PROJECT`, and its test fixtures were reworked.
- `package.json` targets Unity `2021.3` instead of `2019.4` and links the documentation, changelog and license; the package skeleton drops `Editor/Gizmos` and `Editor/Scripts`, and gains a README template.

**Test projects**

- `Unity-Tests/2023.2.22f1` is removed; `2022.3.62f3` and `6000.3.1f1` remain.
- The test projects list the package under `testables` instead of carrying their own sample test assemblies, and no longer commit `packages-lock.json` or the OpenUPM registry.

**Repository**

- The README and docs are rewritten; `Deploy-GitHub.md`, `Deploy-npmjs.md` and `Manual-Package-Rename.md` are removed.
- `FUNDING.yml` and the committed `.vscode/` folders are removed; IDE folders are ignored repository-wide, and `.gitattributes` keeps `.sh` on LF and `.cmd` on CRLF.
- The license holder changed.
