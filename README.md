# suzuri-bin

Arch Linux package for [Suzuri](https://github.com/harrywang/suzuri) — a writing
environment built on Zed (Obsidian-style live preview, Typst/LaTeX preview, PDF
pane).

Suzuri is not in the AUR and upstream only ships a prebuilt Linux tarball (or a
full Zed source build), so this repository packages the official release tarball
as `suzuri-bin`.

## Install

From the AUR (once published):

```sh
paru -S suzuri-bin
```

Or straight from a checkout of this repository:

```sh
git clone https://github.com/Cranyozen/suzuri-bin
cd suzuri-bin
paru -Ui
```

## Updating

```sh
paru -Syu
```

The launcher shipped by this package sets `ZED_UPDATE_EXPLANATION`, which
disables Suzuri's built-in GitHub release polling and turns *Check for Updates*
into a pointer at your package manager. Suzuri must not try to self-update into
`/usr/lib/suzuri`, so updates come from here.

## How the automation works

`.github/workflows/aur.yml` runs daily (and on demand) and:

1. resolves the newest upstream release by following the
   `/releases/latest` redirect (no API token, so it cannot hit a rate limit);
2. if `pkgver` is stale, downloads both architecture tarballs, recomputes
   `sha256sums`, and rewrites `PKGBUILD`;
3. regenerates `.SRCINFO` with a real `makepkg` in an `archlinux:base-devel`
   container — `makepkg` refuses to run as root, so the workflow drops to an
   unprivileged user for this step;
4. commits the refresh back to this repository;
5. pushes `PKGBUILD` and `.SRCINFO` to the AUR.

Updating and publishing are intentionally one workflow: commits pushed with the
default `GITHUB_TOKEN` do not trigger new workflow runs, so a separate
publish-on-push workflow would never fire.

Run it manually from the *Actions* tab, optionally forcing a version:

```
Actions → Update PKGBUILD and publish to AUR → Run workflow → version: 0.5.4
```

The same script the workflow uses can be run by hand:

```sh
./scripts/update-pkgbuild.sh              # latest upstream
./scripts/update-pkgbuild.sh --force 0.5.4
```

## Required secret

| Secret | Purpose |
| --- | --- |
| `AUR_SSH_PRIVATE_KEY` | SSH private key authorised by the AUR account that owns `suzuri-bin` |

The matching public key must be added to the AUR account at
<https://aur.archlinux.org/account/>. Pushing to
`ssh://aur@aur.archlinux.org/suzuri-bin.git` with that key creates the package
on first push.

## Packaging notes

- The upstream app directory layout under `/usr/lib/suzuri` is preserved because
  the launcher resolves its main binary through `../libexec/zed-editor`
  relative to itself.
- This deliberately does **not** reuse `/usr/lib/zed/zed-editor`, which the
  official `zed` package owns, so `zed` and `suzuri-bin` can coexist.
- The bundled `lib/*.so` in the tarball are not installed: all of the editor's
  dynamic dependencies are satisfied by current Arch libraries.
- The desktop file is installed as `dev.zed.Zed-Dev.desktop` rather than under
  the upstream file name `app.suzuri.Suzuri.desktop`. Suzuri ships on Zed's
  *dev* channel, so the running binary reports
  `ReleaseChannel::app_id()` == `dev.zed.Zed-Dev` as its Wayland app_id (and as
  `WM_CLASS` on X11), while `script/bundle-linux` names the bundled desktop file
  `app.suzuri.Suzuri`. A compositor matches the app_id against the desktop file
  name, so the mismatch left KDE showing a generic icon in the taskbar.
  `StartupWMClass` is set to the same id as well.

> Upstream inconsistency: `crates/release_channel/src/lib.rs` (`app_id()`) and
> `script/bundle-linux` (`APP_ID`) disagree about the dev-channel identifier.
> This package compensates at install time; the two should really be reconciled
> upstream.
