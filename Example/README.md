# Example app

Minimal iOS app showing over-the-air translations end to end.

## Run

1. Open `Example/SimpleLocalizeExample.xcodeproj`.
2. Press Run (Cmd+R).

It works out of the box with the strings bundled in `SimpleLocalizeExample/en.lproj/Localizable.strings`.

## Connect it to your project

1. Put your project token (Settings -> Credentials) in `ExampleApp.swift`.
2. In SimpleLocalize create the keys `home.title`, `home.subtitle`, `home.greeting`,
   `home.cta`, `home.language`.
3. Publish to `_production` and tap **Refresh translations** in the app.

## What it shows

- `SimpleLocalize.shared.start()` and `enableBundleIntegration()` in `ExampleApp.swift`,
- `Text(simpleLocalized:)`, which is how SwiftUI reads over-the-air strings - the bundle
  integration covers `NSLocalizedString` and UIKit, but not SwiftUI,
- `.simpleLocalizeAware()`, which re-renders the screen when new translations arrive,
- `setLanguage()` behind the language picker.

The Xcode project is generated from `project.yml`; after editing it run `xcodegen generate`.
