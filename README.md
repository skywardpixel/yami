<img src="docs/icon.png" width="96" align="right" alt="Yami">

# Yami

**Y**et **A**nother **M**ihomo **I**nterface — a minimal macOS menu bar app for
[mihomo](https://github.com/MetaCubeX/mihomo).

Yami does three things: keeps one subscription up to date, runs the mihomo core,
and flips the system proxy. Anything you would touch once a year lives in
mihomo's own config, not in this UI.

```
┌─────────────────────────────────────┐
│  CONNECTION                         │
│  Mihomo                      [ ●──] │
│  ● Running · port 7890              │
│  System Proxy                [ ●──] │
│  Routing         [ Loyalsoldier ▾ ] │
│                                     │
│  SUBSCRIPTION                       │
│  ┌───────────────────────────────┐  │
│  │ https://example.com/sub…   ↻  │  │
│  └───────────────────────────────┘  │
│  Updated 2 hours ago                │
│                                     │
│  APP                                │
│  Launch at Login             [ ●──] │
│  View Config                        │
│  Reveal Log                         │
│  Quit Yami                          │
│  Yami 0.3.0 · mihomo 1.19.30        │
└─────────────────────────────────────┘
```

The menu bar mark carries both states independently — the core can run without
the proxy, so a single dimmed→solid ramp would conflate them:

<img src="docs/menubar-states.png" width="544" alt="Menu bar icon states">

*Left to right: both off, core running, proxy on, both on.* Dimmed means the core
is stopped; the badge dot means the system proxy is on.

## Non-goals

No node list or latency testing, no rule editor, no traffic graph, no multiple
profiles, no TUN mode, no port configuration, no themes. The subscription's YAML
decides proxies and rules; Yami never second-guesses it.

## Requirements

- macOS 14+ on Apple Silicon
- An Apple code signing identity — the privileged helper will not load unsigned
- `brew install mihomo`, unless you bundle the core (below)

## Build

SwiftPM plus a bundling script; there is no `.xcodeproj`.

```bash
./build.sh          # debug  → build/Yami.app
./build.sh release  # release
open build/Yami.app
```

`build.sh` picks the first available signing identity; override with
`YAMI_IDENTITY="Developer ID Application: …" ./build.sh release`.

### Bundling the core

`./build.sh release` ships mihomo inside the app, so it runs on machines without
Homebrew. [`scripts/fetch-mihomo.sh`](scripts/fetch-mihomo.sh) downloads a pinned
arm64 release into a gitignored `vendor/` and checks it against a SHA-256
recorded in the script; a debug build bundles it only if it is already there, and
otherwise falls back to `/opt/homebrew/bin/mihomo` at runtime. The binary adds
about 43 MB, and pins the core version to whatever the script says.

Upstream publishes no checksums or signatures for its release assets, so the
recorded hash comes from a download verified by hand. Everything after that first
pin is reproducible — a changed artefact fails the fetch rather than being signed
and shipped. The core is re-signed with your identity and the hardened runtime
before the bundle is sealed, since upstream ships it ad-hoc signed as `a.out`,
which will not notarize.

**mihomo is GPL-3.0.** Yami runs it as a separate process, so Yami itself is not
a derivative work, but bundling the binary *is* redistribution: the licence ships
in `Contents/Resources/mihomo-LICENSE.txt`, and the corresponding source is the
pinned tag at
[MetaCubeX/mihomo](https://github.com/MetaCubeX/mihomo/releases/tag/v1.19.30).
Keep both in step if you bump the version. (Not legal advice — just the thing not
to discover after shipping.)

**Building under a different Apple developer account** requires changing one
thing: `HelperInfo.clientRequirement` and `helperRequirement` in
[`Sources/YamiShared/HelperProtocol.swift`](Sources/YamiShared/HelperProtocol.swift)
pin a team ID. That pin is the security boundary for a root daemon, so it cannot
be derived at runtime — replace `AU534DT7GN` with your own team ID.

All the artwork is drawn from the crescent in
[`MenuBarIcon.swift`](Sources/Yami/MenuBarIcon.swift), so the app icon, the
status item and the figures above cannot drift apart. `Resources/AppIcon.icns`
is generated on first build — delete it to regenerate after changing the mark.
The README figures come from the same tool:

```bash
swiftc -O Sources/Yami/MenuBarIcon.swift tools/GenerateArtwork.swift -o /tmp/makeicon
/tmp/makeicon --png docs/icon.png
/tmp/makeicon --states docs/menubar-states.png
```

## How it works

**The core.** Yami owns the mihomo process — spawn, supervise, restart on config
change, bounded restart budget on crashes. The control API is a unix socket
(`-ext-ctl-unix`) rather than a TCP port, so there is no second port to pick and
no API secret to store; file permissions are the access control.

**The subscription.** mihomo has no concept of a subscription, so this is most of
the actual logic: fetch with a mihomo `User-Agent` (providers serve HTML to
browser UAs), override the keys that decide how Yami reaches the core, strip
listeners the user was never told about, validate with `mihomo -t`, then swap
atomically. A bad subscription can never take a working core down.

**The system proxy.** Changing proxy settings needs root, so a bundled
`SMAppService` daemon does it over XPC — one approval at first use, silent
thereafter. Both ends verify the other's code signature. The helper writes all
network services in a single `SCPreferences` commit rather than shelling out to
`networksetup`.

**Routing.** Providers often ship a single `MATCH` rule and no real routing, so
Yami offers three positions: the subscription's own rules, the
[Loyalsoldier](https://github.com/Loyalsoldier/clash-rules) set (mainland China
and LAN direct, ads rejected, everything else proxied), or Global. Switching
re-renders from the subscription already on disk — no round-trip to the provider,
and it works offline.

**The config viewer.** **View Config** opens a read-only window showing the YAML
the core actually loaded — the subscription with Yami's overrides applied, which
is the thing you would want to check. It is the only window in the app; the
default `.yaml` handler is usually Xcode, which is a poor way to read a config.

**The interlock.** A system proxy is only as good as the core behind it. If the
core stops, the proxy comes down with it; if Yami crashes, the helper undoes the
proxy when the XPC connection drops. Readiness means *serving* — a TCP connect to
the proxy port, not just a live process.

[`DESIGN.md`](DESIGN.md) has the full reasoning, including the failures that
shaped it.

## Releases

Every push to `main` replaces a single rolling prerelease tagged `canary`, so the
newest build is always at a stable URL:

```
https://github.com/skywardpixel/yami/releases/download/canary/Yami.zip
```

Tagged releases are cut by pushing a `v*` tag, which publishes a real release
named for that version.

The version is derived from the commit — build number from the commit count,
short SHA in the version string — and stamped into `Info.plist` before signing,
since editing it afterwards would invalidate the seal.

Artefacts are only published when a Developer ID certificate is configured — see
[docs/RELEASING.md](docs/RELEASING.md). Without one, CI still builds and tests,
but publishes nothing: an ad-hoc build cannot be opened after download *and* its
privileged helper rejects it, so the System Proxy toggle does not work. Shipping
one is a trap rather than a convenience.

With signing configured, every build is notarized and stapled, so a download
opens with no warnings and no terminal commands.

## Tests

```bash
swift test           # pure logic: config rendering, log parsing, port checks
./scripts/verify.sh  # process lifecycle against a real core
```

`verify.sh` runs against a scratch `YAMI_HOME` with its own defaults domain, so
it never touches your real subscription, cache, or system proxy. It does need
port 7890, so it stops a running Yami and puts it back afterwards.

## State

```
~/Library/Application Support/Yami/   config.yaml, api.sock, mihomo's caches (0700)
~/Library/Logs/Yami/core.log
```
