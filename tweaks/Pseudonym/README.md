# Pseudonym

Gives each app its own stable, coherent fake device instead of your real one.

## What it does

Every value derives from `HMAC-SHA256(seed, "<bundleID>:<generation>:<purpose>")`.
That makes it **deterministic**: an app sees the same device on every launch, so
it keeps working normally, while a different app sees an unrelated one. Bumping
an app's `Generation` produces a wholly new identity on demand — that is the
"new phone" lever, pulled deliberately rather than on every launch.

| Hooked | Behaviour |
|---|---|
| `identifierForVendor` | per-app v4 UUID |
| `advertisingIdentifier` | per-app v4 UUID — **unless ATT already returned zeros** |
| `UIDevice.name` | `iPhone` |
| `hw.machine` / `hw.model` / `uname` | a coherent A9–A11 profile |
| `SecItem*` | service/account names namespaced per app+generation |

Two deliberate decisions:

- **ATT zeros are preserved.** If tracking was denied, iOS already returns the
  all-zero UUID. Substituting a plausible fake there would give the app *more*
  than iOS was willing to, so the original is passed through untouched.
- **`systemVersion` is not hooked.** The hardware profiles are limited to
  devices that actually run iOS 16.7.x, so the real version keeps the story
  consistent. Faking it risks contradicting the model we just reported, and a
  model/version pair Apple never shipped is a *stronger* fingerprint than no
  spoofing at all.

## Enabling an app

Spoofing is opt-in. An app absent from the prefs file is untouched, and
`com.apple.*` is refused outright regardless of configuration.

Over SSH (`issh`, user `root`, password `alpine`):

```bash
plutil -insert Apps.com.example.app -json '{"Enabled":true,"Generation":0}' \
  /var/jb/var/mobile/Library/Preferences/com.romeo.pseudonym.plist
killall -9 com.example.app
```

To hand that app a brand-new device, raise its `Generation`:

```bash
plutil -replace Apps.com.example.app.Generation -integer 1 \
  /var/jb/var/mobile/Library/Preferences/com.romeo.pseudonym.plist
```

The seed is generated once by `postinst` and never leaves the device. Deleting
the prefs file and reinstalling produces a new seed, which regenerates *every*
app's identity at once.

## Warnings

- **Keychain namespacing logs you out.** Within an enabled app it also
  namespaces saved credentials and Sign in with Apple state. Expect to sign in
  again, and do not enable it for anything you cannot afford to be locked out of.
- **Do not enable it for banking, payment or authenticator apps.**
- The board ids in `src/PSProfile.m` are from memory and worth verifying against
  real devices — a wrong machine/board pairing defeats the whole point.

## What this cannot do

Client-side hooks cannot touch:

- **DeviceCheck** — 2 bits stored on Apple's servers against the physical
  device; survives a factory reset.
- **App Attest** — Secure Enclave hardware attestation.
- **Sensor calibration fingerprinting** — factory calibration offsets in the
  accelerometer, gyroscope and magnetometer are unique per device and readable
  at high sample rates.
- **IP address** — a different layer; needs a VPN or proxy.

So this defeats ad networks and analytics SDKs, which is what it is for. It does
not defeat anything built on DeviceCheck or App Attest.

## Not built yet

The per-app toggle is plist-driven; there is no PreferenceLoader UI, so enabling
an app means editing the file over SSH as above.

## Building

```bash
docker build -f docker/theos.Dockerfile -t theos-builder .
docker run --rm -v "%cd%:/work" theos-builder tweaks/Pseudonym
cp tweaks/Pseudonym/packages/*.deb repo/debs/ && python tools/build_repo.py
```
