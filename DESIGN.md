# Yami — a minimal Mihomo menu bar app for macOS

*Yet Another Mihomo Interface.*

Yami does three things: keeps one subscription up to date, runs the mihomo core,
and flips the system proxy. Anything a user would only touch once a year belongs
in mihomo's own config file, not in this UI.

## Non-goals

No node list or latency testing, no rule editor, no traffic graph or dashboard,
no multiple profiles, no TUN/enhanced mode, no port configuration, no themes.
The subscription's own YAML decides proxies and rules; Yami never second-guesses it.

---

### Why `allow-lan` stays forced off

Considered and declined. Turning it on with no `authentication` makes the proxy
an open relay for anyone on the network — unremarkable at home, bad on café or
office wifi — and it is a once-a-year setting, which belongs in the config rather
than the UI.

The honest counterpoint is that it is currently *impossible* rather than merely
hidden: the override rewrites it on every update, so there is no route to sharing
the proxy with a phone or a TV. If that is ever wanted, two things change
together:

- **`PortGuard` must follow the bind address.** With `allow-lan`, mihomo binds
  `0.0.0.0` rather than `127.0.0.1`, and binding `127.0.0.1` over a wildcard
  listener *succeeds* with `SO_REUSEADDR` — measured, not assumed. The
  availability check would go blind to both port conflicts and orphaned cores,
  which is the exact failure already fixed once.
- **The status line must show the bind address**, so `0.0.0.0:7890` is visible
  and the exposure is never silent.

## The whole interface

`MenuBarExtra` in `.window` style — one popover, ~280pt wide. The window style
(rather than a native `NSMenu`) is chosen for exactly one reason: it can hold the
URL text field, so there is no second settings window anywhere in the app.

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

Editing the URL and pressing return saves it and immediately fetches. Everything
else is a single click.

**Status line** is the only place errors appear. It has five states:

| State | Text | Dot |
|---|---|---|
| stopped | `Stopped` | grey |
| starting | `Starting…` | grey, pulsing |
| running | `Running · port 7890` | green |
| core exited | `Core exited — Reveal Log` | red |
| subscription failed | `Update failed: <reason>` | amber, config unchanged |

Opening the popover re-reads the system proxy and login-item state: both can be
changed behind Yami's back in System Settings, and a switch that lies is worse
than no switch.

The core, the system proxy and the login item are all plain on/off state, so they
all get the same control. An earlier version used a power button for the core and
a switch for the proxy, which implied they were different kinds of thing.

The controls sit in three labelled groups. **Connection** holds everything that
decides how traffic behaves — the core, the system proxy, and routing. Routing is
*implemented* by re-rendering the subscription, but that is Yami's problem, not
the user's: under a heading reading SUBSCRIPTION it looked like a property of the
URL box above it. **Subscription** is then only the URL and its update.
**App** is Yami's own settings and actions.

An earlier version put a divider between every control, which in a 280pt popover
read as a list of unrelated switches. Headings say what a group is rather than
only where it ends, so the dividers went with them — doing both is twice the
separation needed.

Every control and action row shares one height, so a switch does not stand taller
than the plain rows beneath it and the column keeps a single rhythm.

The three actions below them are full rows, not a row of links. Link-blue reads
as "opens a web page" rather than a local action, a run of text buttons is a
small target, and fitting three across 256pt forced abbreviating "View Config"
to "Config" — losing the verb. Rows highlight under the pointer, and the first
has its focus ring suppressed since no menu row draws one.

**The mark** is a crescent, drawn rather than borrowed from SF Symbols. It nods
at the name (闇, darkness), has a distinctive silhouette among the squarish icons
in a menu bar, and — because it is a solid shape built from two circles rather
than a stroked or detailed glyph — stays crisp at 15pt. The `globe` symbol tried
first collapsed into a grey blob at that size.

It is built from the true circle-circle intersection, as two arcs meeting at the
horns. The obvious approach — fill one disc, subtract another — does not work:
the subtracting disc has to overhang the outer one, since that overhang is what
forms the horns, and an even-odd fill paints the overhang too, turning the mark
into a broken ring.

**The menu bar icon** carries the two states *orthogonally*, because they are not
stages of one process — the core can run without the proxy, and a single
dimmed→solid→filled ramp would conflate them:

| | proxy off | proxy on |
|---|---|---|
| **core stopped** | crescent at 40% | 40% + badge dot |
| **core running** | crescent at full tint | full + badge dot |

Dimmed rather than hidden: a stopped core should still be findable in the bar.
The canvas is the same size in all four states and the mark is centred in it —
sizing the canvas to fit the badge would shift the crescent every time the proxy
was switched on. A transparent moat is punched around the badge so it reads as
separate from the mark. Everything is a template image: colour in the menu bar
reads as an alert, and the system handles light/dark and highlighting. The state
is also spelled out in the accessibility label, since a dimmed mark and a badge
dot are not self-explanatory.

**The app icon** is the same crescent, pale on a deep indigo-to-black gradient in
the standard macOS rounded-rect. It is generated by `tools/GenerateArtwork.swift` at build
time rather than checked in as an opaque binary, so the two marks cannot drift
apart.

---

## State

```swift
@Observable final class AppModel {
    var core: CoreState          // .stopped | .starting | .running(port: Int) | .exited(String)
    var systemProxy: Bool
    var subscriptionURL: String
    var lastUpdated: Date?
    var updateError: String?
    var busy: Bool               // disables the two toggles + Update
}
```

Four components hang off it, each with one job:

- **`CoreController`** — owns the `Process`. Launches
  `mihomo -d <appSupport> -f config.yaml -ext-ctl-unix <appSupport>/api.sock`.
  A unix-socket controller instead of a TCP one means no port to pick, no API
  secret to manage, and file permissions are the access control. After spawn it
  polls `GET /version` over the socket until 200 or a 3s timeout, then reports
  `.running`. `terminationHandler` moves state to `.exited`. stdout/stderr stream
  to `~/Library/Logs/Yami/core.log`. Unexpected exits restart at most 3 times
  before giving up — no infinite respawn loop.
- **`SubscriptionStore`** — fetches, validates, installs. Details below.
- **`ProxyController`** — XPC client for the privileged helper.
- **`HelperInstaller`** — `SMAppService.daemon(...)` registration and status.

---

**The About line** names both versions, because "which Yami, which core" is the
first question about any misbehaviour. Yami's own version is derived from `git
describe` at build time rather than a checked-in constant: a tagged build reads
`0.3.0`, anything else reads `0.3.0-4-g1a2b3c4`, and an uncommitted tree adds
`-dirty`. A hand-maintained number goes stale exactly when it matters — an
install lagging behind the repository looked identical to a current one until
this changed. The core version is read by running the
binary Yami would actually launch — hardcoding it would drift the moment the core
is bundled, upgraded, or falls back to Homebrew — and the row's tooltip gives the
path, so it is clear whether the bundled core or Homebrew's is in use. The text is
selectable, since it exists to be pasted into a bug report.

### The config viewer

The one window in the app, and a deliberate exception to the popover rule: a
read-only view of the YAML mihomo is actually running, opened from **View
Config**.

Handing the file to the system's default `.yaml` handler would have been smaller,
but on a developer's Mac that handler is usually Xcode — a ten-second launch to
read a proxy config. Revealing it in Finder is not viewing it. So the window
earns its place: it opens instantly and shows exactly what the core loaded.

It is backed by an `NSTextView` rather than a SwiftUI `Text` in a `ScrollView`.
A subscription with a few hundred nodes runs to hundreds of kilobytes, which
`Text` with selection enabled does not handle gracefully, and `NSTextView` brings
⌘F along for free. Setting its string leaves the scroller at the end of the
document, so it is explicitly scrolled back to the top — a config is read from
the top, and Yams' alphabetical dump puts Yami's own overrides there.

Read-only and labelled as generated: the file is rewritten on every update, so an
edit made here would silently disappear. It shows node passwords and keys in
plaintext because the config contains them; there is deliberately no share or
export affordance.

## Routing

The one place Yami overrides what a subscription ships, and only when asked.
There is still no rule editor: the choice is between three whole positions.

| | |
|---|---|
| **Subscription** | The provider's rules and rule-providers, untouched |
| **Loyalsoldier** | [clash-rules](https://github.com/Loyalsoldier/clash-rules) — proxy by default, mainland China and LAN direct, ads rejected |
| **Global** | A single `MATCH` sending everything through the provider's group |

This earns its place because providers frequently ship nothing worth keeping —
the subscription this was built against contains exactly one rule, `MATCH,JMS`,
so "use the provider's routing" means "no routing at all".

**Rewriting the policy is what makes a public rule set usable.** Loyalsoldier's
rules target a group literally named `PROXY`, which no subscription is obliged
to define. Yami substitutes the group the provider's own `MATCH` rule points at,
falling back to its first group — that is where a provider states which group it
considers "the proxy".

**`Global` is deliberately not mihomo's `mode: global`.** That routes through the
GLOBAL selector, whose selection defaults to `DIRECT` and does not persist
without `store-selected`. Measured on a live core: switching to it would have
silently sent everything direct — the opposite of what the name promises. A
single `MATCH` rule says what it does and survives a restart.

**Why no ACL4SSR or blackmatrix7.** Not laziness — their rules reference ten or
more named policy groups (`🚀 节点选择`, `🌍 国外媒体`, and so on) that a plain
subscription does not define. Supporting them means synthesizing a whole
proxy-group structure and mapping each onto the provider's nodes. Loyalsoldier
drops in cleanly precisely because it only ever targets `DIRECT`, `PROXY` and
`REJECT` — one substitution. Any future addition needs that same property.

**Costs worth knowing.** The rule lists are fetched by the core at runtime and
refreshed daily, so routing depends on a third party that decides what gets
rejected and what bypasses the proxy. A first start with no network leaves those
rules unmatched, and traffic falls through to `MATCH`. `GEOIP` rules pull a
MMDB database on first use.

## Subscription handling

A mihomo binary has no concept of a subscription — that is entirely a client-side
job, and it is most of Yami's actual logic.

1. **Fetch** the URL with `URLSession`, `User-Agent: mihomo/1.19.30`. Many
   providers gate their config on a recognised client UA and will hand a browser
   UA an HTML page instead of YAML.
2. **Override.** Provider YAML is trusted for `proxies`, `proxy-groups` and
   `rules`, and overridden everywhere else, because those keys decide how Yami
   itself talks to the core:

   ```yaml
   mixed-port: 7890          # one port for HTTP and SOCKS5
   allow-lan: false          # never expose the proxy to the network
   mode: rule
   log-level: warning
   external-controller: ""   # TCP controller off; the unix socket is the only API
   ```

   Alongside the overrides, a set of keys is *removed* rather than replaced —
   `port`, `socks-port`, `redir-port`, `tproxy-port`, `secret`, `external-ui`
   and the other `external-controller-*` variants. A provider that sets these
   would otherwise open listeners the user was never told about.

   This needs a real YAML round-trip — duplicate top-level keys are an error in
   Go's `yaml.v3`, so overrides cannot simply be prepended to the downloaded text.
   **[Yams](https://github.com/jpsim/Yams) is the app's single dependency**:
   decode to `[String: Any]`, set the five keys, re-encode. Comments and key order
   are lost, which does not matter for a generated file.
3. **Validate** by writing to `config.yaml.new` and running
   `mihomo -t -d <dir> -f config.yaml.new`. This is the whole reason a bad
   subscription can never take the core down.
4. **Install** with an atomic replace, then restart the core if it was running.
   A failure at any step leaves the previous `config.yaml` untouched and surfaces
   in the status line.

### Pre-flight: the "alive but not serving" trap

Readiness means *serving*, not merely alive: `/version` on the control socket
proves the process started, and a TCP connect to the mixed port proves the proxy
real traffic will hit is actually up. Both must pass. If the mixed port fails to bind, mihomo stays up and Yami would
report `Running · port 7890` over a proxy carrying no traffic — which, with the
system proxy pointed at it, takes the machine offline. Two checks run before
every launch:

- **Reap orphans.** A SIGKILLed Yami leaves its core alive, holding the proxy
  port and the config cache. Matching on the socket path in `argv` identifies
  cores Yami spawned and nothing else, so a mihomo the user runs by hand or
  under `brew services` is never touched.
- **Test the port.** Attempt a bind on 127.0.0.1:7890 **with `SO_REUSEADDR`**,
  and name the listener in the error if it fails. This machine has Clash Verge
  installed, so a foreign port holder is realistic rather than hypothetical.

  `SO_REUSEADDR` is load-bearing, and getting it wrong cost a debugging session.
  The check must be *exactly* as permissive as Go's `net.Listen`, which is what
  mihomo uses. A client that leaks its connection — Chrome does — leaves
  mihomo's side of the socket in `FIN_WAIT_2` holding the port after the core is
  terminated. A plain bind then fails `EADDRINUSE` on a port mihomo would have
  bound without complaint, so every config reload with a browser attached
  reported a phantom port conflict. A real `LISTEN` still fails the check, which
  is the only case worth catching.

- **Failing pre-flight must not be terminal.** A port conflict can be transient,
  so it spends the normal restart budget before giving up. The first version
  treated it as permanent and parked the app in `.exited` until relaunched —
  which, combined with the interlock below, silently turned the user's proxy off
  and left no way back.

**Auto-refresh:** whenever `lastUpdated` is more than 24h old — checked at
launch, on an hourly tick, when the Mac wakes, and when the popover opens. No
interval setting, no scheduler.

The first version checked only at launch, which quietly meant *never*: a menu bar
app runs for weeks, so the 24-hour policy could not fire for anyone who did not
quit daily. The hourly tick is cheap and the interval check decides whether
anything is actually fetched; the wake notification exists because a sleeping
Mac's timers do not fire, and waking is exactly when a subscription is most
likely to have gone stale. The policy is a pure function so it can be tested.

**Storage:**

```
~/Library/Application Support/Yami/
  config.yaml       # generated — subscription + overrides
  api.sock          # mihomo's unix external-controller
  cache.db, geoip.metadb, …   # mihomo's own artifacts, it owns this dir
~/Library/Logs/Yami/core.log
```

The URL and `lastUpdated` live in `UserDefaults`. The URL usually embeds a token,
so Keychain is tempting — but `config.yaml` sitting next to it already contains
every node's password in plaintext, so Keychain for the URL alone buys nothing
real. Protect the directory (`0700`) instead.

---

## System proxy and the privileged helper

Changing proxy settings requires root. A bundled `SMAppService` daemon takes one
admin approval at first use and is silent forever after.

**Bundle layout**

```
Yami.app/Contents/
  MacOS/Yami
  MacOS/dev.yami.helper
  Library/LaunchDaemons/dev.yami.helper.plist   # BundleProgram + MachServices
```

Registration: `try SMAppService.daemon(plistName: "dev.yami.helper.plist").register()`,
called lazily the first time the user flips System Proxy on — not at launch, so a
user who never enables the proxy is never prompted. The prompt sends them to
System Settings ▸ Login Items; `.status` drives a one-line "Approve Yami in Login
Items" message in the popover until it reads `.enabled`.

**Protocol** (one file shared by both targets):

```swift
@objc protocol YamiHelper {
    func setProxy(enabled: Bool, port: Int, reply: @escaping (String?) -> Void)
    func proxyState(reply: @escaping (Bool) -> Void)
}
```

**Client verification is the security-critical part.** A root daemon with an open
Mach service is a local privilege-escalation hole. `listener(_:shouldAcceptNewConnection:)`
must take the connection's `auditToken`, resolve it with
`SecCodeCopyGuestWithAttributes`, and check it against a designated requirement
pinning the team ID and `dev.yami` bundle identifier. Reject otherwise.

**Implementation** uses `SCPreferences` directly, not shell-outs. Running as root
it opens the current network set, walks `SCNetworkSetCopyServices`, and writes the
HTTP, HTTPS and SOCKS proxy dictionaries on each enabled service, then commits and
applies once. Two reasons over `networksetup`: a single commit reconfigures every
interface atomically instead of N separate ones, and a root daemon that spawns
shell commands built from caller-supplied strings is a footgun worth not building.

Bypass list, fixed:

```
127.0.0.1, localhost, *.local, 10.0.0.0/8, 172.16.0.0/12,
192.168.0.0/16, 100.64.0.0/10, 17.0.0.0/8
```

(`100.64.0.0/10` keeps Tailscale working — this machine has a Tailscale service.
`17.0.0.0/8` is Apple's, for push.)

**The dead-proxy problem.** If Yami quits or crashes while the system proxy points
at 127.0.0.1:7890, the core dies with it and the machine loses all network access —
the single worst failure this app can cause. Two defences:

- Graceful quit turns the proxy off before terminating the core.
- The helper remembers that *it* enabled the proxy and disables it on
  `invalidationHandler` when the app's XPC connection drops. A crash self-heals
  within a second.

---

## Targets and signing

```
Yami/
  Yami.xcodeproj
  Yami/                       # app target, macOS 14+
    YamiApp.swift             # MenuBarExtra
    AppModel.swift
    PopoverView.swift
    Core/CoreController.swift
    Core/ConfigWriter.swift
    Core/SubscriptionStore.swift
    Core/PortGuard.swift        # orphan reaping + port availability
    Core/LogSink.swift          # core.log + last-error ring
    Core/UnixSocketHTTP.swift   # readiness probe
    Proxy/ProxyController.swift
    Proxy/HelperInstaller.swift
  Helper/                     # dev.yami.helper — command-line tool target
    main.swift                # NSXPCListener(machServiceName:)
    ProxyService.swift        # SCPreferences
    dev.yami.helper.plist
  Shared/HelperProtocol.swift
```

**Not sandboxed.** Spawning an external binary and vending a root daemon are both
incompatible with the App Sandbox. Hardened runtime on, Developer ID signed.

**The mihomo binary:** `Paths.mihomo` prefers `Contents/MacOS/mihomo` and falls
back to `/opt/homebrew/bin/mihomo`, so a debug build needs no download and a
release build carries its own core. `scripts/fetch-mihomo.sh` pins the version
and verifies a recorded SHA-256 — upstream publishes no checksums of its own, so
the first pin is trust-on-first-use and everything after it is reproducible.

The core is re-signed with the team identity and the hardened runtime *before*
the bundle is sealed, for the same nested-code-first reason as the helper:
upstream ships it ad-hoc signed with `Identifier=a.out` and no runtime flag,
which fails notarization.

Bundling costs about 43 MB, pins the core version to the app's release cadence,
and makes the app a redistributor of GPL-3.0 software — the licence ships in
`Contents/Resources`, and the README records the tag the bytes came from.

**Port 7890** is hardcoded. If the port is already bound at launch — this machine
currently has a client on 7897, so a stale one is plausible — the core will fail
to start and the status line says so rather than the app trying to negotiate.

---

## Build order

1. ~~**Shell.** `MenuBarExtra`, `AppModel`, `CoreController`.~~ **Done.**
2. ~~**Subscription.** Fetch → Yams overrides → `mihomo -t` → atomic install →
   restart.~~ **Done**, plus the pre-flight checks above.
3. **Helper.** Second target, `SMAppService` registration, XPC with client
   verification, `SCPreferences` toggle, auto-off on disconnect.
4. **Polish.** Launch at login (`SMAppService.mainApp`), Reveal Log, icon states,
   24h auto-refresh, error strings.

Each step is independently usable, and step 3 is the only one with real risk in it.
