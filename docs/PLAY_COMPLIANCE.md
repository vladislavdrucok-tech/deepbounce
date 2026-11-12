# Deep Bounce — Google Play compliance sheet

Answers for Play Console → *Policy → App content*, based on the shipped implementation (version 1.1.1, code 6,
package `com.deepbounce.game`). Re-check after any SDK change.

## Implementation facts these answers rely on

| Item | Fact (where to verify) |
|---|---|
| Account / login | none; no personal data entered by the user |
| Game data | local save file + local diagnostic log in app-private storage; never transmitted by the game (`scripts/game_state.gd`) |
| Ads | Google Mobile Ads SDK 24.9.0 via own plugin `android_plugins/deepbounce-ads`; rewarded (second chance, double crystals) and interstitial (between runs/levels, capped: not in first 3 runs, then ≥3 runs and ≥180 s, never after a rewarded run) — `scripts/ads.gd`, `config/monetization.cfg` |
| Consent | Google UMP 3.2.0: consent info requested at every launch, form shown when required, SDK initialized and ads requested only while `canRequestAds()` is true, privacy options entry in Settings when required |
| Ad-Free owners | ads SDK never started |
| Purchases | Google Play Billing Library 9.1.0 (official GodotGooglePlayBilling 3.3.0); 7 permanent + 4 consumable one-time products |
| Permissions (manifest) | INTERNET, ACCESS_NETWORK_STATE, VIBRATE, com.google.android.gms.permission.AD_ID, ACCESS_ADSERVICES_AD_ID / _ATTRIBUTION / _TOPICS (added by the Ads SDK), com.android.vending.BILLING, WAKE_LOCK, FOREGROUND_SERVICE (SDK internals) |
| Target / min SDK | target 36, min 24, 64-bit (arm64-v8a, x86_64), AAB |
| Other SDKs | none (no analytics, crash reporting or social SDKs) |

## Privacy policy
URL: the public HTTPS address where `site/index.html` is hosted (English only). Not yet hosted — see `site/README.md`.

## App access
"All functionality is available without special access" (no login, no paywall-locked core gameplay).

## Ads
**Yes, my app contains ads.**

## Content rating (IARC questionnaire)
- Category: **Game**.
- Violence: none (abstract stones are broken; no characters, creatures or blood).
- Fear, sexuality, profanity/crude humor, drugs/alcohol/tobacco, discrimination: **No**.
- Gambling / simulated gambling: **No** (no loot boxes; every purchase delivers a known item).
- User interaction / user-generated content / sharing location / communication: **No**.
- Digital purchases: **Yes**.
- Expected result: PEGI 3, ESRB Everyone, USK 0, IARC 3+.

## Target audience and content
- Age groups: **13–15, 16–17, 18 and over**. Do **not** select under-13 groups (Families policy would require
  child-directed ad settings and certified ad networks; the current ad configuration is not child-directed).
- "Could your store listing unintentionally appeal to children?" — answer honestly; the art is stylized but neutral.
  If Google flags it, keep the 13+ audience and confirm ads comply (max ad content rating PG is set).

## Advertising ID declaration
**Yes**, the app uses an advertising ID — purposes: **Advertising or marketing**, **Analytics**, **Fraud prevention,
security, and compliance** (Google Mobile Ads SDK).

## Data safety form

**Does your app collect or share any of the required user data types?** Yes (through the Google Mobile Ads SDK).
**Is all of the user data collected by your app encrypted in transit?** Yes.
**Do you provide a way for users to request that their data is deleted?** The developer holds no user data; game data
is deleted with the app. Answer according to Play's current wording ("No" for account-based deletion is acceptable
when there is no account; mention Google's controls in the privacy policy).

| Data type | Collected | Shared | Processing | Required/optional | Purposes |
|---|---|---|---|---|---|
| Location → Approximate location | Yes | Yes (Google) | Not ephemeral | Required for the free version | Advertising or marketing, Fraud prevention |
| App activity → App interactions | Yes | Yes (Google) | Not ephemeral | Required for the free version | Advertising or marketing, Analytics |
| App info and performance → Crash logs, Diagnostics | Yes | Yes (Google) | Not ephemeral | Required for the free version | Analytics, Fraud prevention |
| Device or other IDs | Yes | Yes (Google) | Not ephemeral | Required for the free version | Advertising or marketing, Analytics, Fraud prevention |
| Financial info → Purchase history | handled by Google Play, not by the developer | — | — | — | Not declared by the developer per Google guidance for Play Billing |

Reference: https://developers.google.com/admob/android/privacy/play-data-disclosure (verify against the current page
before submitting — Google updates it).

## Government / financial / health / news / COVID-19
No / no financial features / no / no / no.

## UMP consent (AdMob → Privacy & messaging)
Create and **publish** a "European regulations" message (EEA, UK, Switzerland) and, optionally, a "US state
regulations" message; link the privacy policy URL. Without a published message the consent form never appears.

## app-ads.txt
At the root of the developer website listed in the Play store listing: one line
`google.com, pub-<your publisher id>, DIRECT, f08c47fec0942fa0` (template: `site/app-ads.txt.template`).

## Release gating
`tools/android/check_store_ready.sh` must print READY before a production build: real AdMob IDs (not Google test
IDs), `use_test_ads=false`, Play licence key, signing key present in the environment.
