# Unity Package Starter Kit

Template for Unity Package Manager packages: a package project, an installer, test projects for several Unity versions, and CI that tests, signs and releases the package to OpenUPM.

> [!NOTE]
> This README describes the template. `commands/init.ps1` replaces it with the package README skeleton from `Unity-Package/Assets/root/README.md`.

## Layout

| Path | Purpose |
|---|---|
| `Unity-Package/Assets/root/` | The package itself. Everything outside this folder is not shipped. |
| `Installer/` | Project that exports the installer `.unitypackage` (adds the OpenUPM registry and pins the version). |
| `Unity-Tests/<version>/` | Empty projects that reference the package as a local, testable dependency, one per tested Unity version. |
| `commands/` | Init, version bump, consistency check and "open all projects" scripts. |
| `.github/workflows/` | Test matrix and release pipeline (`*.yml-sample` until init). |
| `docs/` | Release and signing guides. |

## Create a package

### 1. Create the repository

Create a new repository from this template on GitHub and clone it.

### 2. Initialize

Requires [PowerShell 7](https://learn.microsoft.com/powershell/scripting/install/installing-powershell) (`pwsh`).

```powershell
./commands/init.ps1 -PackageId "com.company.cool-package" -PackageName "Cool Package" -GitHubRepository "User/cool-package" -InstallerExtraPath "Editor"
```

| Parameter | Description |
|---|---|
| `-PackageId` | Reverse-domain package name, e.g. `com.company.cool-package`. |
| `-PackageName` | Display name, e.g. `Cool Package`. |
| `-GitHubRepository` | `owner/repo` slug, used for links, badges and release URLs. |
| `-RootNamespace` | Optional C# root namespace. Defaults to `Company.CoolPackage`, derived from the id and name, because package ids may contain `-`. |
| `-InstallerExtraPath` | Optional folder between `Assets/` and the installer folder, e.g. `Editor`. Prompted when omitted. |

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
./commands/open-all-projects-unix.sh
```

On Windows run `./commands/open-all-projects-windows.ps1`. You can also add `Installer` and `Unity-Package` to Unity Hub and open them by hand.

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
bash commands/check-package.sh
```

The script needs no Unity license (only `git` and `jq`) and runs first in CI. It checks that:

- every JSON, manifest and `.asmdef` file parses,
- `package.json`, `Installer.cs` and both changelogs agree on the version,
- the package copies of `README.md` and `CHANGELOG.md` match the root files,
- every package asset has a `.meta` file, no `.meta` file is orphaned, and GUIDs are unique.

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
| `UPM_INSTALL_SHA256` | variable | SHA-256 of the pinned UPM CLI install script |

Signing is a hard gate: without the `UPM_*` values no release is created. [`docs/openupm-signing.md`](docs/openupm-signing.md) explains how to get them.

### Workflows

- **test** runs on pull requests to `main` and `dev` that touch the package, the test projects or the installer. The license-free checks run first; then the package tests run on every Unity version in `Unity-Tests/` in EditMode, PlayMode and Standalone, and the installer tests run in EditMode. Only the projects a PR touches are tested, and a new push cancels the previous run.
- **release** runs only on demand (**Actions > release > Run workflow**). It fails if the version tag already exists, runs the full test matrix, builds the signed tarball and both `.unitypackage` files, attests them and publishes the tag and GitHub Release in one step.
- **test-unity-plugin** is the reusable job that runs one Unity test mode for one project.

Dependabot keeps the pinned action versions up to date.

To test another Unity version, add a project to `Unity-Tests/`, then update the matrix in `test.yml` and the lists in the `open-all-projects` scripts.

## Release

```powershell
./commands/bump-version.ps1 -NewVersion "1.0.1"
```

Then add the changelog entry, merge and run the release workflow. See [`docs/Deploy-OpenUPM.md`](docs/Deploy-OpenUPM.md) for the full checklist and the one-time OpenUPM setup.
