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
7. **Duo layout**: TikTok fills the Duo's inner display edge to edge (relinked at the iOS 27.1 SDK) with
   its own plain bottom tab bar in every pose (no glass, no custom rail). Unfolded landscape also gets
   TikTok's own tablet layout — its split shell: Profile, Inbox and similar screens open in a side panel
   beside the feed, the bar along the bottom of the main column. Unfolded portrait (669pt, below TikTok's
   816pt breakpoint) and folded stay phone layout. `patch_duo.sh` must not change `DTXcode` (2700): the
   816pt breakpoint and the full-width main column both key off it.

All seven are on by default and toggle in `NSUserDefaults` (keys in `LiquidTok.h`); there's no settings
screen yet, so changing one means a default write (a future sidebar menu, like LiquidBird's logo menu).

## Layout
- `LiquidTok.h`   switch keys; runtime-messaging helpers that check a selector's return type first (so a
  dropped or changed selector is a no-op, not a crash); `LTIsShopKey` (shop/mall/ecom name match).
- `Tweak.x`       the feed filter and Shop removal. A post that's an ad/sponsored/product/AI is dropped from
  the parsed list (`-setAwemeList:` on the feed, profile, hashtag and sound response models), judged on the
  model's commerce/AIGC/product fields. Never filter by returning nil from `AWEAwemeModel
  -initWithDictionary:error:`: TikTok parses a page with Mantle, one nil post fails the whole page, and the
  feed stops refreshing. Your own Saved/Liked lists aren't filtered. Also off: overlay info cards, the
  avatar follow badge, LIVE (corner item `TTKFeedTabCornerLiveItem`, in-feed lives), the search teaser.
  Shop is taken out of the tab configs TikTok builds its bars from (`TTKFeedTopTabControlConfig`,
  `TTKTabEntranceResult`, `TTKTabFCPConfigCheckResult`, `TTKFeedTopTabEntranceConfig`) and, as a backstop,
  out of `TTKTabBarController buttonsForTabBar`. Splash ads off via `AWESplashManager`/`BDASplashManager`.
- `Tracking.x`    the SDK silencers: `BDTrackerProtocol`/`TTTracker` event log, `HMDTTMonitor`, `AppsFlyerLib`,
  `FIRAnalytics`, `FBSDKAppEvents`, plus `ASIdentifierManager`/`ATTrackingManager`. Each `%orig` is gated on
  the switch so flipping it off restores TikTok's own behaviour.
- `Tiling.x`      the Duo layout: TikTok's own bottom bar in every pose (no glass — its Liquid Glass tab bar
  gate pinned off, UIKit's chrome around/inside the stand-in `TTKFakeTabBar` hidden), TikTok's split shell
  on for the unfolded tablet layout, a compact width override so the bar stays a bottom bar, search/corner
  items inside the safe area, TikTok's own `TTKABTest` Duo fixes on, shorter bar. Change layout only from
  real frames (the dumps, `scripts/dump_receiver.sh`), never by guessing from screenshots.
- `Debug.x`       four-finger long press (three is the Duo's system copy/paste) copies the view/VC hierarchy,
  the tab bar/corner/side-panel frames in window coordinates and the filter tally to the pasteboard.
  A diagnostic build (workflow input `dump_url`) also POSTs that dump to `scripts/dump_receiver.sh` on the
  Mac mini at launch and whenever the window shape or the screen on top changes. Defines `LTLog`.
- `LiquidTok.plist`  bundle filter (`com.zhiliaoapp.musically`).
- `scripts/verify_ipa.py`  the trust gate: the base IPA is a decrypted build from a stranger's GitHub
  release, so before anything is injected this checks it's still Apple's — every Mach-O carries its App
  Store CMS signature chained to Apple Root CA, every unencrypted page (and the header, cryptid restored)
  hashes to the code directory, every sealed resource is unchanged and nothing unsealed was added. The
  decrypted `__TEXT` itself can't be checked (Apple hashed it encrypted). `build.sh` runs it; it needs
  macOS (`/usr/bin/openssl`, the system root keychain).
- `scripts/patch_duo.sh`  on the verified base IPA: raises TikTok's linked SDK 27.0 -> 27.1 (`vtool`), the
  iPhone Duo full-edge layout; leaves `UIDesignRequiresCompatibility` false as shipped (true makes TikTok
  hand its real tab bar to UIKit, which squeezes it into the Duo's status strip); bumps `CFBundleVersion`
  per run, or iOS won't install a new build over the old one.
- `scripts/build.sh`   fetch the base IPA (`BASE_IPA_URL`, default the pinned 47.5.0 release), **verify it**,
  patch it, `make package`, inject with `cyan`. Output `out/LiquidTok.ipa` (unsigned).
- `.github/workflows/build.yml`  job `ipa`: the pipeline on macOS runners (unsigned, no secrets); job
  `sign`: ad-hoc signs it (`fastlane/Fastfile`, match certs from gi-os/ios-certs) as `com.gios.liquidtok`
  for every registered device, strips app extensions, uploads `LiquidTok-adhoc` encrypted, deletes the
  unsigned artifact. Never a public release.
- `scripts/install_link.sh [run-id] [minutes]`  on the Mac mini: serves a run's `LiquidTok-adhoc` as a
  tap-to-install link (Cloudflare quick tunnel, random path, stops after 20 min). Decrypts with
  `~/.config/liquidbird/artifact-key.pem` (the same key pair as LiquidBird's). Send Giovanni the link.
- `scripts/dump_receiver.sh [minutes]`  on the Mac mini: write-only receiver for a diagnostic build's layout
  dumps behind a quick tunnel; prints the `dump_url` to build with
  (`gh workflow run build.yml -R gi-os/LiquidTok -f dump_url=<url>`). Dumps land in `/tmp/lt-dumps`.
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
