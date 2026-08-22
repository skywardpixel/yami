# Signed and notarized releases

Until a Developer ID certificate is configured, CI builds and tests but
**publishes no artefacts**. That is deliberate: an ad-hoc signed build cannot be
opened after download, and its privileged helper rejects it, so the System Proxy
toggle does not work. Shipping one is a trap.

Everything below is done once, by you. **Do not paste any of these values into a
chat, an issue, or a commit** — they go straight into GitHub's secret store.

## 1. Enrol in the Apple Developer Program

$99/year, at <https://developer.apple.com/programs/>. A free Apple ID cannot
issue a Developer ID certificate, and Developer ID is what makes a downloaded app
open without warnings.

## 2. Check your Team ID

Visible at <https://developer.apple.com/account> under Membership, or in the
`OU` field of any certificate:

```bash
security find-identity -v -p codesigning
```

**If it is not `AU534DT7GN`, change `HelperInfo.teamID` in
[`Sources/YamiShared/HelperProtocol.swift`](../Sources/YamiShared/HelperProtocol.swift)
to match.** That constant is what the privileged helper checks before accepting a
connection; if it does not match the certificate the app is signed with, the
helper refuses every request and the System Proxy toggle silently stops working.
Enrolling can move you from a personal team to an organisation team, which
changes the ID.

## 3. Create a Developer ID Application certificate

Xcode ▸ Settings ▸ Accounts ▸ select the team ▸ Manage Certificates ▸ **+** ▸
*Developer ID Application*. Requires the Account Holder or Admin role.

Then export it **with its private key**: Keychain Access ▸ My Certificates ▸
right-click the certificate ▸ Export ▸ `.p12`, and set a password.

## 4. Create an App Store Connect API key for notarization

App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store Connect API ▸
Keys ▸ **+**. Give it the *Developer* role.

Download the `.p8` — **it can only be downloaded once** — and note the **Key ID**
and the **Issuer ID** shown on that page.

An API key is preferred over an Apple ID and app-specific password: it is
scoped, revocable on its own, and carries no account password.

## 5. Add the GitHub secrets

Repository ▸ Settings ▸ Secrets and variables ▸ Actions ▸ New repository secret.

| Secret | Value |
|---|---|
| `MACOS_CERT_P12` | base64 of the `.p12` from step 3 |
| `MACOS_CERT_PASSWORD` | the password you set on that `.p12` |
| `NOTARY_KEY_P8` | base64 of the `.p8` from step 4 |
| `NOTARY_KEY_ID` | the Key ID |
| `NOTARY_ISSUER_ID` | the Issuer ID |

To produce the base64 values:

```bash
base64 -i /path/to/certificate.p12 | pbcopy   # paste into MACOS_CERT_P12
base64 -i /path/to/AuthKey_XXXX.p8 | pbcopy   # paste into NOTARY_KEY_P8
```

Delete the local `.p12` and `.p8` afterwards, or move them into a password
manager. The `.p8` cannot be re-downloaded.

## 6. Prove it locally first (optional but recommended)

Before trusting CI with it, store a notarytool profile — this stays on your
machine, so no key material passes through the repository:

```bash
xcrun notarytool store-credentials yami \
    --key ~/Downloads/AuthKey_XXXXXXXX.p8 \
    --key-id XXXXXXXXXX \
    --issuer xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
```

Then:

```bash
./build.sh release
./scripts/notarize.sh
```

It refuses to submit anything not signed with a Developer ID certificate, and
ends by printing Gatekeeper's verdict — the same check a downloader's Mac makes.

## 7. Push

The next push to `main` publishes a signed, notarized `canary`; pushing a `v*`
tag publishes a release. CI imports the certificate into a throwaway keychain,
signs with a secure timestamp, submits to Apple, waits for the result, staples
the ticket into the bundle, and verifies with `spctl` before publishing — so a
notarization failure fails the build rather than shipping a broken artefact.

## Rotating or revoking

Certificates expire after five years and API keys can be revoked at any time.
Replace the secret values; nothing in the repository needs to change. If the
signing certificate moves to a different team, update `HelperInfo.teamID` as in
step 2.
