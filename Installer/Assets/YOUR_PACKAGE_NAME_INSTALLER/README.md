# YOUR_PACKAGE_NAME Installer

This folder installs [YOUR_PACKAGE_NAME](https://github.com/YOUR_GITHUB_USERNAME_REPOSITORY) through Package Manager.

On the next domain reload the installer:

- registers the OpenUPM scoped registry in `Packages/manifest.json`, and
- pins `YOUR_PACKAGE_ID` to the installer's version.

Package Manager then downloads and manages the real package, so dependencies resolve automatically and updates work as with any other package. The installer never downgrades: it only writes the version when the installer's version is newer than the one already pinned.

Once the package is installed, this folder can be deleted.
