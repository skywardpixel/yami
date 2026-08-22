<img src="docs/icon.png" width="96" align="right" alt="Yami">

# Yami

**Y**et **A**nother **M**ihomo **I**nterface — a minimal macOS menu bar app for
[mihomo](https://github.com/MetaCubeX/mihomo).

Yami does three things: keeps one subscription up to date, runs the mihomo core,
and flips the system proxy. Anything you would touch once a year lives in
mihomo's own config, not in this UI.

```
┌─────────────────────────────────────┐
│  Mihomo                      [ ●──] │
│  ● Running · port 7890              │
├─────────────────────────────────────┤
│  System Proxy                [ ●──] │
├─────────────────────────────────────┤
│  SUBSCRIPTION                       │
│  ┌───────────────────────────────┐  │
│  │ https://example.com/sub?tok…  │  │
│  └───────────────────────────────┘  │
│  Updated 2 hours ago      [Update]  │
├─────────────────────────────────────┤
│  Reveal Log              Quit Yami  │
└─────────────────────────────────────┘
```

The menu bar mark carries both states independently — the core can run without
the proxy, so a single dimmed→solid ramp would conflate them:

<img src="docs/menubar-states.png" width="560" alt="Menu bar icon states">

*Left to right: both off, core running, proxy on, both on.* Dimmed means the core
is stopped; the badge dot means the system proxy is on.

## Non-goals

No node list or latency testing, no rule editor, no traffic graph, no multiple
profiles, no TUN mode, no port configuration, no themes. The subscription's YAML
decides proxies and rules; Yami never second-guesses it.

## Requirements

- macOS 14+
- `brew install mihomo`
- An Apple code signing identity — the privileged helper will not load unsigned

## Build

SwiftPM plus a bundling script; there is no `.xcodeproj`.

```bash
./build.sh          # debug  → build/Yami.app
./build.sh release  # release
open build/Yami.app
```

`build.sh` picks the first available signing identity; override with
`YAMI_IDENTITY="Developer ID Application: …" ./build.sh release`.

**Building under a different Apple developer account** requires changing one
thing: `HelperInfo.clientRequirement` and `helperRequirement` in
[`Sources/YamiShared/HelperProtocol.swift`](Sources/YamiShared/HelperProtocol.swift)
pin a team ID. That pin is the security boundary for a root daemon, so it cannot
be derived at runtime — replace `AU534DT7GN` with your own team ID.

`Resources/AppIcon.icns` is generated from the crescent in
[`MenuBarIcon.swift`](Sources/Yami/MenuBarIcon.swift) on first build; delete it
to regenerate after changing the mark.

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

**The interlock.** A system proxy is only as good as the core behind it. If the
core stops, the proxy comes down with it; if Yami crashes, the helper undoes the
proxy when the XPC connection drops. Readiness means *serving* — a TCP connect to
the proxy port, not just a live process.

[`DESIGN.md`](DESIGN.md) has the full reasoning, including the failures that
shaped it.

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
