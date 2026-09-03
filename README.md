# SimpleLocalize OTA SDK for Apple platforms

[![CI](https://github.com/simplelocalize/simplelocalize-ota-sdk-apple/actions/workflows/ci.yml/badge.svg)](https://github.com/simplelocalize/simplelocalize-ota-sdk-apple/actions/workflows/ci.yml)

Over-the-air translations for iOS, macOS, tvOS and watchOS apps. Translations are fetched at
runtime from [SimpleLocalize Translation Hosting](https://simplelocalize.io) (`cdn.simplelocalize.io`),
so fixing a typo or adding a language is a **publish**, not an App Store release.

- No dependencies, no build phase, ~700 lines of Swift.
- Works with existing `NSLocalizedString` / SwiftUI `Text("key")` call sites (opt-in), or through
  an explicit API.
- Offline first: last downloaded content is cached on disk, strings compiled into the app stay the
  final fallback.
- Cheap refresh: conditional `If-None-Match` requests, so an unchanged refresh transfers no body.

## Installation

Swift Package Manager - in Xcode (**File → Add Package Dependencies…**) or in `Package.swift`:

```swift
.package(url: "https://github.com/simplelocalize/simplelocalize-ota-sdk-apple.git", branch: "main")
```

Tagged releases will follow; until then pin a commit if you need reproducible builds.

## Quick start

```swift
import SimpleLocalizeOTA

@main
struct MyApp: App {
  init() {
    SimpleLocalize.shared.start(
      SimpleLocalizeConfiguration(
        projectToken: "5a5b1f...",   // Settings -> Credentials, public by design
        environment: "_production",  // "_latest" for dev builds
        fallbackLanguage: "en"
      )
    )
  }
}
```

Read strings:

```swift
label.text = SLLocalizedString("home.title")
label.text = "home.title".simpleLocalized
label.text = "cart.items".simpleLocalized(arguments: 3)   // "%d items in cart"
```

`start(_:)` is non-blocking: it loads the disk cache synchronously (so the first frame already has
the last known translations) and refreshes in the background.

## Zero-touch integration with NSLocalizedString

```swift
SimpleLocalize.enableBundleIntegration()
```

This swaps the class of `Bundle.main`, so `NSLocalizedString` and `Bundle.main.localizedString`
- and with them UIKit code, storyboards and XIBs - resolve through the SDK first and fall back to
the `.strings` / String Catalog compiled into the app. No call site changes.

**SwiftUI is not covered.** `Text("key")` and `String(localized:)` do not ask
`Bundle.main.localizedString`, so they keep rendering the bundled text (verified on Xcode 26 /
iOS 26). In SwiftUI read strings explicitly - it is one initializer away:

```swift
Text(simpleLocalized: "home.title")
Text("home.title".simpleLocalized)
Text(localization.string("home.title"))
```

Caveat: views already on screen are not re-rendered when new translations arrive. Observe
`SimpleLocalize.translationsDidChangeNotification`, or in SwiftUI use `.simpleLocalizeAware()`.

## SwiftUI

```swift
struct ContentView: View {
  @StateObject private var localization = SimpleLocalizeObservable()

  var body: some View {
    VStack {
      Text(localization.string("home.title"))
      Text(simpleLocalized: "home.subtitle")
      Button("Polski") { localization.setLanguage("pl") }
    }
    .simpleLocalizeAware()   // rebuilds when translations change
  }
}
```

## Configuration

| Option | Default | Meaning |
|---|---|---|
| `projectToken` | – | Settings -> Credentials |
| `environment` | `_production` | `_latest`, `_production` or a custom environment key |
| `baseURL` | `https://cdn.simplelocalize.io` | change it for a custom hosting provider (S3/GCS/Azure) |
| `namespaces` | `[]` | downloaded namespaces; a namespace maps to the `table` of `NSLocalizedString` |
| `language` | `nil` | forced language key; `nil` resolves it from `Locale.preferredLanguages` |
| `fallbackLanguage` | `nil` | language used for keys missing in the current one |
| `customerId` | `nil` | customer specific translations (`{language}_{customerId}`) |
| `minimumRefreshInterval` | `600 s` | throttle for automatic refreshes |
| `refreshOnForeground` | `true` | refresh when the app becomes active |
| `session` | `.shared` | inject your own `URLSession` |
| `logHandler` | `nil` | diagnostics sink |

## How lookup works

1. over-the-air translation in the current language,
2. over-the-air translation in `fallbackLanguage`,
3. string compiled into the app (`.strings` / String Catalog),
4. the key itself.

Over-the-air content is a **per-key overlay on top of the app's own resources**, never a
replacement: anything that is not published keeps rendering the string compiled into the app, key
by key on the same screen. An empty translation counts as missing, so publishing missing
translations as empty strings does not blank out the UI.

The same layering applies to the network: memory, then the disk cache, then the app. A failed
refresh - offline, HTTP error, unpublished resource - never drops content already downloaded, and
an app launched offline with an empty cache simply shows its bundled strings.

Two limits worth knowing:

- The overlay only reaches call sites that go through the SDK (see the two sections above);
  plurals always stay with the bundled resources, see [Roadmap](#roadmap).
- If everything published for the resolved language disappears from hosting (404 on every
  resource), the SDK forgets that language and falls back to the bundled strings, even when it
  still holds them in the cache.

Language keys are matched against the device locale in this order: `en_GB`, `en-GB`, `en` - the
first one published on the CDN wins and is remembered across launches.

Hosting can publish flat (`{"home.title": "Hi"}`) or nested (`{"home": {"title": "Hi"}}`) JSON;
both are supported and nested payloads are flattened to dot separated keys.

## Refresh model

- `start(_:)` - disk cache immediately, network refresh in the background.
- app foreground - throttled by `minimumRefreshInterval`.
- `SimpleLocalize.shared.refresh()` - manual, ignores the throttle.

`_production` is served with `Cache-Control: max-age=3600`, so a publication reaches users within
about an hour; point debug builds at `_latest` to iterate faster.

## Roadmap

- Plurals (`.stringsdict`) are not supported yet.

## Example app

A runnable iOS app lives in [`Example/`](Example) - open `Example/SimpleLocalizeExample.xcodeproj` and press Run.

## Development

```bash
swift build
swift test
```
