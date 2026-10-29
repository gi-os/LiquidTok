# LiquidTok

Theos tweak injected into a decrypted App Store **TikTok** IPA (`com.zhiliaoapp.musically`, base pinned at
47.5.0, built with the iOS 27 SDK). Personal sideload only, same shape as its sibling [[LiquidBird]] — not a
kit app (no `ci/app.env`), so `.github/mac/setup.sh` won't touch it; the clone here was placed by hand.

## Goals
A TikTok with none of the stuff Giovanni doesn't want, and a layout that works on the iPhone Duo:
1. **No ads**: in-feed, TopView and search ads, pseudo-ads (ad copies of organic posts), and the launch
   splash ad.
2. **No sponsored**: paid partnerships (branded content), Spark Ads' soft ads, and Promote's boosts.
3. **No product posts**: anything selling via TikTok Shop — product-link (cart) anchors, product photos,
   shopping ads, product cards.
4. **No AI posts**: anything TikTok labels AI-generated (the creator's label or its own moderation one).
5. **No TikTok Shop**: the Shop bottom tab, the Shop home top-tab, and the Shop entrances, out of the bars.
6. **No tracking**: ByteDance's event log, Heimdallr telemetry, AppsFlyer, Firebase, Facebook; IDFA zeroed
   and App Tracking Transparency answered "denied" with no prompt. (Likes/follows/comments still work —
   they're API calls, not events — so For You learns less but isn't blind.)
7. **Duo sidebar**: on the Duo's wide poses the bottom tab bar becomes a floating glass rail down the
   trailing strip, so the video keeps the whole screen; plain iPhones and the folded pose stay stock.

All seven are on by default and toggle in `NSUserDefaults` (keys in `LiquidTok.h`); there's no settings
screen yet, so changing one means a default write (a future sidebar menu, like LiquidBird's logo menu).

## Layout
- `LiquidTok.h`   switch keys; runtime-messaging helpers that check a selector's return type first (so a
  dropped or changed selector is a no-op, not a crash); `LTIsShopKey` (shop/mall/ecom name match).
- `Tweak.x`       the feed filter and Shop removal. A post that's an ad/sponsored/product/AI comes back nil
  from `AWEAwemeModel -initWithDictionary:error:`, so no feed, profile grid or search result shows it
  (BHTikTok's `isAds` filter, widened to the other four over the model's commerce/AIGC/product fields).
  Shop is taken out of the tab configs TikTok builds its bars from (`TTKFeedTopTabControlConfig`,
  `TTKTabEntranceResult`, `TTKTabFCPConfigCheckResult`, `TTKFeedTopTabEntranceConfig`) and, as a backstop,
  out of `TTKTabBarController buttonsForTabBar`. Splash ads off via `AWESplashManager`/`BDASplashManager`.
- `Tracking.x`    the SDK silencers: `BDTrackerProtocol`/`TTTracker` event log, `HMDTTMonitor`, `AppsFlyerLib`,
  `FIRAnalytics`, `FBSDKAppEvents`, plus `ASIdentifierManager`/`ATTrackingManager`. Each `%orig` is gated on
  the switch so flipping it off restores TikTok's own behaviour.
- `Tiling.x`      the Duo sidebar. On a window >= 600pt wide, or one with the side status-bar strip
  (`LTSideStrip`), TikTok's `TTKTabBar` fades out and a glass rail of snapshots of its own
  `TTKTabBarButton`s is drawn down the strip; a tap forwards to `TTKTabBarController setSelectedIndex:`.
  Snapshots (not our own icons) so the rail always matches TikTok's current art, Shop already removed.
- `Debug.x`       three-finger long press copies the view/VC hierarchy + the filter tally to the pasteboard,
  for Giovanni to paste; how class names get verified without FLEX. Defines `LTLog`.
- `LiquidTok.plist`  bundle filter (`com.zhiliaoapp.musically`).
- `scripts/verify_ipa.py`  the trust gate: the base IPA is a decrypted build from a stranger's GitHub
  release, so before anything is injected this checks it's still Apple's — every Mach-O carries its App
  Store CMS signature chained to Apple Root CA, every unencrypted page (and the header, cryptid restored)
  hashes to the code directory, every sealed resource is unchanged and nothing unsealed was added. The
  decrypted `__TEXT` itself can't be checked (Apple hashed it encrypted). `build.sh` runs it; it needs
  macOS (`/usr/bin/openssl`, the system root keychain).
- `scripts/build.sh`   fetch the base IPA (`BASE_IPA_URL`, default the pinned 47.5.0 release), **verify it**,
  `make package`, inject with `cyan`. Output `out/LiquidTok.ipa` (unsigned).
- `.github/workflows/build.yml`  job `ipa`: the pipeline on macOS runners (unsigned, no secrets); job
  `sign`: ad-hoc signs it (`fastlane/Fastfile`, match certs from gi-os/ios-certs) as `com.gios.liquidtok`
  for every registered device, strips app extensions, uploads `LiquidTok-adhoc` encrypted, deletes the
  unsigned artifact. Never a public release.
- `scripts/install_link.sh [run-id] [minutes]`  on the Mac mini: serves a run's `LiquidTok-adhoc` as a
  tap-to-install link (Cloudflare quick tunnel, random path, stops after 20 min). Decrypts with
  `~/.config/liquidbird/artifact-key.pem` (the same key pair as LiquidBird's). Send Giovanni the link.
- `scripts/register_link.sh [minutes]`  on the Mac mini: one-time link that captures a new device's UDID;
  then `gh workflow run build.yml -f udid=<udid> -f device_name=<name>` registers it and re-signs.
- `scripts/objc_dump.py` / `objc_find.py` / `objc_dis.py`  (shared with LiquidBird) read class/metadata and
  disassembly out of the app's frameworks, for finding and confirming class names without FLEX.

## Rules
- Class names are from TikTok 47.5's ObjC metadata (dump `Frameworks/MusicallyCore.framework/MusicallyCore`,
  which holds the app's classes). Confirm anything unsure in FLEX (inject FLEXing: `build.sh --flex`, or run
  the workflow with `flex`) or with `Debug.x`'s dump. Prefer accessibility labels/identifiers over private
  class names where it's a view; they survive app updates.
- Guard every iOS 26 API with `if (@available(iOS 26, *))`. Deployment target stays 15.0.
- Placeholder/unverified hooks live in their own `%group`, `%init`ed in `%ctor` only if `objc_getClass`
  finds the class; keep it that way (a nil class crashes at launch).
- No global hooks on `UIView -layoutSubviews`; too hot. `UIControl` and the tab classes are fine.
- Never commit IPAs, decrypted binaries, or signing certs. `.gitignore` covers them. The base IPA is never
  committed or re-released — `build.sh` fetches it.
- The repo is public (free macOS minutes), so the signed IPA goes up encrypted (see `install_link.sh`).
  Signing secrets (synced from gi-os/ios-certs) go only to the `sign` job, which runs no third-party code.

## Commands
- `make package FINALPACKAGE=1`   builds `packages/*.deb`
- `./scripts/build.sh`            end to end, output `out/LiquidTok.ipa` (verifies the base IPA first)
- There's no PR check (not a kit app); validate a branch with
  `gh workflow run build.yml -R gi-os/LiquidTok --ref <branch>` and watch with `gh run watch`.
