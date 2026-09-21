# Tailscale for LG webOS Homebrew

A [Tailscale](https://tailscale.com/) client packaged as a [webOS Homebrew
Channel](https://www.webosbrew.org/) app for **rooted LG webOS smart TVs**.
It bundles the official `tailscale`/`tailscaled` binaries so the TV joins
your existing tailnet as a full mesh-VPN node — no extra software needed on
the desktop side, and no router port forwarding needed for
[Moonlight](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide)/[Sunshine](https://github.com/LizardByte/Sunshine)
game streaming (or anything else on your tailnet) once the tunnel is up.

*Keywords: Tailscale on LG TV, webOS Homebrew Channel VPN app, rooted webOS
TV Tailscale/WireGuard client, Moonlight/Sunshine game streaming over
Tailscale without port forwarding, tailscaled full-TUN on webOS.* If you
searched for something like that and landed here, this is probably the
project you were looking for — see [Status](#status) below before relying on
it.

---

## What this is (and isn't)

- **Is:** a way to make a rooted LG webOS TV a first-class node on your
  tailnet, so anything else on that tailnet (a desktop running Sunshine, a
  NAS, another server) is reachable from the TV by its Tailscale IP, from
  anywhere — home network or not.
- **Isn't:** a way to root your TV. Root is a hard *prerequisite* — see
  [Requirements](#requirements) and [Status](#status).
- **Isn't** affiliated with or endorsed by Tailscale Inc., WireGuard, or LG —
  see [Trademarks](#trademarks--credits).

---

## Status

**Not yet validated on real hardware.** The code, build pipeline and IPK
packaging are complete and pass every check that doesn't require a physical
TV (script sandbox tests, binary/tag inspection, full `make package && make
verify` runs — see [Project layout](#project-layout)). Nobody has installed
it on an actual rooted webOS TV and confirmed the tunnel and Moonlight
actually work end to end.

**If you have a rooted LG webOS TV with Homebrew Channel, testers are
wanted.** Install it, work through [First-time setup](#first-time-setup),
and open an issue (or a PR) with what happened — especially anything in
[Known risks / open questions](#known-risks--open-questions).

Root itself is the harder blocker for most people: as of this writing, no
public exploit covers very recent webOS builds (webOS 22 / internal 7.x and
newer). Check your exact model and firmware at
[CanI.RootMy.TV](https://cani.rootmy.tv/) before assuming this project is
usable on your TV. If nothing there roots your firmware, this project isn't
viable on that specific TV yet — a future exploit release could change that,
or an older/rollback-able unit might already work.

---

## Requirements

- Rooted LG webOS TV (see [Status](#status) — check root feasibility first)
- Homebrew Channel installed, with its root service available
- `/dev/net/tun` support on the TV (already required by, and confirmed
  working through, the WireGuard Homebrew app referenced below)

The package bundles binaries for both:

```text
linux/arm   (ARMv7, 32-bit)
linux/arm64 (aarch64, 64-bit)
```

`install.sh` picks the right one automatically based on `uname -m`, run on
the TV itself — deliberately more conservative than a single-architecture
build, since this is meant to run on whatever hardware a community tester or
user happens to have, not just one confirmed device.

---

## Installation

### 1. Build or download the IPK

To build manually:

```sh
make package
```

This requires:

- Go (for cross-compiling `tailscale`/`tailscaled` — pure Go, `CGO_ENABLED=0`,
  no cross toolchain needed)
- `ares-package`, from either LG's `@webos-tools/cli` or webOSBrew's
  `ares-cli-rs`. Set `ARES_PACKAGE=/path/to/ares-package` if it isn't on
  `PATH`.
- A POSIX shell with `make`, `git`, `file`, `ar` and `tar` (Git Bash works
  on Windows).

**Building on Windows:** it works, with two caveats. Packagers running on
Windows cannot record the executable bit, so the resulting IPK ships its
scripts and binaries as non-executable; `install.sh` restores the bits on the
TV, and `make verify` prints a warning. For an official release, build on
Linux, WSL or CI so the modes are correct from the start. Also, the build
clones Tailscale with `core.autocrlf=false` so `build_dist.sh` isn't broken by
CRLF conversion.

`scripts/build-binaries.sh` clones `tailscale/tailscale` into `.build/` (not
committed) and builds with the official `build_dist.sh --extra-small --box`
helper. `--extra-small` strips unused features to shrink the binary; `--box`
adds the `ts_include_cli` build tag, which is what folds `tailscale` and
`tailscaled` into one binary using the busybox-style argv0 trick (without it,
the `tailscale` symlink would not work as a CLI). Pin a specific release with
`TAILSCALE_REF=v1.x.y make package`.

Output:

```text
dist/com.github.tailscale-webos-tv.tailscale-tv_0.1.0_all.ipk
```

### 2. Install using Homebrew Channel

Copy or upload the IPK to your TV and install it from Homebrew Channel.

### 3. Open the app

Press **Install / update** first. This prepares persistent state under:

```text
/var/lib/webosbrew/tailscale-tv
```

The packaged binaries and scripts stay inside the application directory;
only auth key, tailscaled state (node identity) and logs live under
`/var/lib/webosbrew/tailscale-tv`, symlinked to the packaged payload — so
updates take effect without duplicating binaries.

---

## First-time setup

1. Generate a **reusable auth key** at
   [console.tailscale.com/admin/settings/keys](https://console.tailscale.com/admin/settings/keys).
   Interactive browser login isn't practical with a TV remote, so this project
   only supports auth-key-based login (see [Tailscale's auth key docs](https://tailscale.com/docs/features/access-control/auth-keys)).
   Consider tagging the key so the TV is identifiable in your tailnet, and
   treat it as a secret — it is never bundled in the `.ipk`.
2. Open the app, press **Install / update**.
3. Type the key into the auth key field, press **Save auth key**.
4. Press **Start**.
5. Press **Status** to confirm `tailscale0` is up and the node shows as
   `Running`.
6. Point Moonlight (or whatever else) on the TV at the target device's
   Tailscale IP.

The auth key is stored at `/var/lib/webosbrew/tailscale-tv/conf/authkey`
(mode `600`) and is only read once, on the first successful `tailscale up`;
after that, the persisted node key in `tailscaled`'s state directory is
enough, so `tailscaled` reconnects on its own — including across reboots, if
autostart is enabled.

---

## Autostart

Enabling **Start on boot** creates:

```text
/var/lib/webosbrew/init.d/90-tailscale-tv
```

a symlink to the packaged `boot.sh`. During boot, the script waits (up to
20s) for a default route, then starts Tailscale. If the app is removed, the
link becomes non-executable and Homebrew's hook runner skips it — no
"ghost" tunnel keeps trying to start.

---

## Uninstall

The **Uninstall** button logs the node out of your tailnet (so it doesn't
linger as a device in your account), stops Tailscale, and removes:

```text
/var/lib/webosbrew/tailscale-tv
/var/lib/webosbrew/init.d/90-tailscale-tv
```

After that, remove the app from Homebrew Channel.

---

## Security notes

- The `.ipk` never contains an auth key. You type it into the app on first
  setup; it is written directly to the TV's local filesystem via the
  Homebrew root service, not uploaded anywhere.
- Reusable auth keys are sensitive — anyone with the key can register a
  device on your tailnet until it expires (90 days by default) or is
  revoked. Revoke it from the admin console if you ever remove the TV.
- No ACLs are configured by this project; the TV behaves like any other
  node on your tailnet (see `docs/handoff-tailscale-webos-moonlight.md` for
  that decision and its rationale).
- Rooting a TV and running unofficial root-level software on it is inherently
  higher-risk than a normal app install — see [Disclaimer](#disclaimer).

---

## Known risks / open questions

- **Not yet validated on real hardware.** See [Status](#status).
- **Root exploit availability is a moving target.** What's rootable changes
  over time (new exploits appear, firmware gets patched); check
  [CanI.RootMy.TV](https://cani.rootmy.tv/) for your specific model and
  firmware rather than assuming.
- **Firmware updates can undo root/Homebrew.** Not specific to this
  project — any rooted-TV app is exposed to this.
- **Binary size.** `tailscaled` is larger than `wireguard-go` alone even
  after `--extra-small`; if the app partition is tight, this may need
  revisiting (UPX was considered but skipped for the W^X caveat Tailscale's
  own docs call out — see `docs/handoff-tailscale-webos-moonlight.md`).
- **Trademarks.** See [Credits](#trademarks--credits).

---

## Project layout

```text
app/com.github.tailscale-webos-tv.tailscale-tv/
  appinfo.json
  index.html
  css/
  js/
  lib/
  icon.png                      (80x80, original artwork — see below)
  payload/tailscale/
    install.sh
    bin/
      tailscale.combined.armv7  (built, not committed)
      tailscale.combined.arm64  (built, not committed)
    scripts/
      start.sh
      stop.sh
      status.sh
      set-authkey.sh
      autostart.sh
      boot.sh
      uninstall.sh

scripts/
  build-binaries.sh
  package.sh
  verify-release.sh
```

### Icon

`app/com.github.tailscale-webos-tv.tailscale-tv/icon.png` is an 80x80 PNG
(the LG-recommended launcher size): a TV with three linked nodes on screen.
It is original artwork and intentionally does not reuse or imitate the
Tailscale logo, in line with the trademark note below.

---

## Publishing to the community repository

Once this has been validated by at least one real tester (see
[Status](#status) — the [webOS Homebrew apps-repo](https://repo.webosbrew.org/submit)
review process is **not** a substitute for that: it screens submissions
before listing them, but its own rules reject AI-assisted contributions
submitted without meaningful human testing), submitting means:

1. Cutting a GitHub release with the built `.ipk` attached, tagged to match
   `appinfo.json`'s `version`.
2. Updating `com.github.tailscale-webos-tv.tailscale-tv.manifest.json`'s
   `ipkUrl` to point at that release asset (already the convention this file
   follows).
3. Opening a PR against `webosbrew/apps-repo` adding a
   `com.github.tailscale-webos-tv.tailscale-tv.yml` entry, per their
   submission guide, disclosing AI assistance as their rules require.

---

## Contributing & forking

This project is released for anyone to use, fork, and modify — see
[License](#license). If you have a rooted TV to test on, hardware you'd like
to add support for, or a fix for something in
[Known risks / open questions](#known-risks--open-questions), forks and pull
requests are welcome. There's no formal process: open an issue or a PR.

---

## Disclaimer

This is an independent, community/personal project, shared as-is in case it's
useful to others — it is **not** a commercial product and comes with no
support guarantee. Rooting a TV and running root-level software on it can
void warranties, and — while the underlying exploits and tools are widely
used and documented — carries some risk of misconfiguring or bricking the
device if used incorrectly. Use it entirely at your own risk. In line with
the [MIT License](LICENSE) it's released under, the software is provided
"as is", without warranty of any kind, and its authors and contributors are
not liable for any damages or issues arising from its use.

---

## Trademarks & credits

This project only exists because of the tools and prior work below. "Tailscale"
and "WireGuard" are trademarks of their respective owners (Tailscale Inc. and
Jason A. Donenfeld); this project is not affiliated with either, and its
package ID intentionally avoids implying an official release
(`com.github.<repo>.<app>`, the same convention `webos-wireguard`, credited
below, uses).

- **[Tailscale](https://tailscale.com/)** ([tailscale/tailscale](https://github.com/tailscale/tailscale),
  BSD-3-Clause) — the VPN this project packages. Builds on WireGuard.
- **[WireGuard](https://www.wireguard.com/)**, by Jason A. Donenfeld — the
  underlying protocol/engine (`wireguard-go`) Tailscale embeds.
- **[`webos-wireguard`](https://github.com/cfernande1470/webos-wireguard)**
  (MIT) — this project's structure and Homebrew integration pattern
  (privileged exec via the Homebrew root service, symlinked boot hook, state
  kept outside the app directory) directly mirror it, and it's the proof that
  this class of userspace tunnel works on this hardware in the first place.
- **[webOS Homebrew Channel](https://www.webosbrew.org/)**
  ([webosbrew](https://github.com/webosbrew)) — the root service, app
  platform and community this project packages for.
- **[Moonlight](https://github.com/moonlight-stream)** and
  **[Sunshine](https://github.com/LizardByte/Sunshine)** — the game-streaming
  stack this project's primary use case is built around.
- LG's `@webos-tools/cli` and webOSBrew's
  [`ares-cli-rs`](https://github.com/webosbrew/ares-cli-rs) — packaging
  tooling (`ares-package`) used to build the IPK.

---

## License

The app-specific code (packaging, scripts, UI) is licensed under the
[MIT License](LICENSE) — permissive and fork-friendly by design. The bundled
`tailscale`/`tailscaled` binaries retain their own license:
[BSD-3-Clause](https://github.com/tailscale/tailscale/blob/main/LICENSE).
