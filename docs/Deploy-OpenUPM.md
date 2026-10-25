# Releasing to OpenUPM

[OpenUPM](https://openupm.com/) builds its index from public GitHub repositories. This repository publishes every release as a GitHub Release with a signed UPM tarball, and OpenUPM serves that tarball.

## Once

1. Make the GitHub repository public.
2. Configure the CI secrets and the `UPM_INSTALL_SHA256` variable (see [`openupm-signing.md`](openupm-signing.md)).
3. [Submit the package to OpenUPM](https://openupm.com/packages/add/) using the repository URL.
4. Switch the OpenUPM listing to `trackingMode: githubRelease` with `githubReleaseAssetName: 'tarball-YOUR_PACKAGE_ID-'` **before** the first release (see [`openupm-signing.md`](openupm-signing.md#4-file-the-openupm-listing-change)).

## Every release

1. Bump the version everywhere it appears:

   ```powershell
   ./commands/bump-version.ps1 -NewVersion "1.0.1"
   ```

2. Add a `## [1.0.1] - YYYY-MM-DD` entry to `CHANGELOG.md` and copy the file to `Unity-Package/Assets/root/CHANGELOG.md`.
3. Run the license-free checks and fix anything they report:

   ```bash
   bash commands/check-package.sh
   ```

4. Merge to `main`, then run the **release** workflow from the **Actions** tab.

The release workflow fails if the tag already exists, runs the same tests as pull requests, and only then creates the tag and the GitHub Release with three assets:

| Asset | Contents |
|---|---|
| `tarball-YOUR_PACKAGE_ID-<version>.tgz` | Signed UPM package, consumed by OpenUPM |
| `installer-YOUR_PACKAGE_ID-<version>.unitypackage` | Editor script that adds the OpenUPM registry and pins the version |
| `YOUR_PACKAGE_ID-<version>.unitypackage` | Package sources for `Assets/Plugins/YOUR_PACKAGE_NAME_PASCAL/`, without Package Manager |

Every asset carries a GitHub build provenance attestation:

```bash
gh attestation verify <file> --repo YOUR_GITHUB_USERNAME_REPOSITORY
```

OpenUPM usually picks up a new release within 30 minutes.
