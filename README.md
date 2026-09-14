# Tailscale for LG webOS Homebrew

A Tailscale client for rooted LG webOS TVs using Homebrew Channel. It packages
the official `tailscale`/`tailscaled` binaries as a webOS app so the TV joins
your existing tailnet as a full node — no extra app is needed on the desktop
side, and no port forwarding is needed for [Moonlight](https://github.com/moonlight-stream/moonlight-docs/wiki/Setup-Guide)/[Sunshine](https://github.com/LizardByte/Sunshine)
streaming once the tunnel is up.

The project structure and Homebrew integration pattern (privileged exec via
the Homebrew root service, symlinked boot hook, state kept outside the app
directory) mirror [`webos-wireguard`](https://github.com/cfernande1470/webos-wireguard),
which already proves this class of userspace tunnel works on this hardware.

---

## Status

This has **not been tested on real hardware yet**. The maintainer's own TV is
not rooted, so this project is being developed and validated through the
[webOS Homebrew apps-repo](https://repo.webosbrew.org/submit) review process,
which tests submissions before merging. If you have a rooted LG TV with
Homebrew Channel and are willing to test before this is submitted upstream,
please open an issue.

---

## Requirements

- Rooted LG webOS TV
- Homebrew Channel installed, with its root service available
- `/dev/net/tun` support on the TV (already required by, and confirmed
  working through, the WireGuard Homebrew app)

The package bundles binaries for both:

```text
linux/arm   (ARMv7, 32-bit)
linux/arm64 (aarch64, 64-bit)
```

`install.sh` picks the right one automatically based on `uname -m`, run on
the TV itself — this is deliberately more conservative than the WireGuard
project's single-ARMv7-build approach, since this package is meant to run on
whatever hardware a community tester or user happens to have, not just one
confirmed device.

---

## Installation

### 1. Build or download the IPK

Release package:

```text
com.github.arthru-vinicius.tailscale-tv_0.1.0_all.ipk
```

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

`scripts/build-binaries.sh` clones `tailscale/tailscale` into `.build/` (not
committed) and builds with the official `build_dist.sh --extra-small` helper,
which combines `tailscale` and `tailscaled` into one binary using the
busybox-style argv0 trick (`ts_include_cli`-equivalent behavior baked into
`--extra-small` when targeting `cmd/tailscaled`). Pin a specific release with
`TAILSCALE_REF=v1.x.y make package`.

Output:

```text
dist/com.github.arthru-vinicius.tailscale-tv_0.1.0_all.ipk
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
updates take effect without duplicating binaries, matching the pattern
`webos-wireguard` settled on in its 1.0.2 release.

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
6. Point Moonlight on the TV at the desktop's Tailscale IP.

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
  node on your tailnet (see the original handoff doc for that decision).

---

## Known risks / open questions

- **Not yet validated on real hardware.** See [Status](#status).
- **Firmware updates can undo root/Homebrew.** Not specific to this
  project — any rooted-TV app is exposed to this.
- **Binary size.** `tailscaled` is larger than `wireguard-go` alone even
  after `--extra-small`; if the app partition is tight, this may need
  revisiting (UPX was considered upstream in the handoff doc but skipped
  here for the same W^X caveat Tailscale's own docs call out).
- **Trademarks.** "Tailscale" and "WireGuard" are trademarks of their
  respective owners; this project's package ID intentionally avoids
  implying an official release (`com.github.<user>.<app>`, same convention
  `webos-wireguard` uses).

---

## Project layout

```text
app/com.github.arthru-vinicius.tailscale-tv/
  appinfo.json
  index.html
  css/
  js/
  lib/
  icon.png                      (add before packaging — see below)
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

`app/com.github.arthru-vinicius.tailscale-tv/icon.png` is not included yet —
add a square PNG (80x80 is the LG-recommended launcher size) before running
`make package`.

---

## Publishing to the community repository

Once this has been validated by at least one real tester (see
[Status](#status)), submitting to the
[webOS Homebrew apps-repo](https://repo.webosbrew.org/submit) means:

1. Cutting a GitHub release with the built `.ipk` attached, tagged to match
   `appinfo.json`'s `version`.
2. Updating `com.github.arthru-vinicius.tailscale-tv.manifest.json`'s
   `ipkUrl` to point at that release asset (already the convention this file
   follows).
3. Opening a PR against `webosbrew/apps-repo` adding a
   `com.github.arthru-vinicius.tailscale-tv.yml` entry, per their submission
   guide. Their team reviews and tests submissions before merging — this is
   the de facto hardware validation path for this project until the
   maintainer (or a volunteer) has a rooted TV to test on directly.

---

## License

The app-specific code (packaging, scripts, UI) is licensed under the
[MIT License](LICENSE). The bundled `tailscale`/`tailscaled` binaries retain
their own license: [BSD-3-Clause](https://github.com/tailscale/tailscale/blob/main/LICENSE).
