import SwiftUI
import SimpleLocalizeOTA

/// Replace with the project token from Settings -> Credentials in SimpleLocalize.
let projectToken = "YOUR_PROJECT_TOKEN"

@main
struct ExampleApp: App {

  init() {
    SimpleLocalize.shared.start(
      SimpleLocalizeConfiguration(
        projectToken: projectToken,
        environment: "_production",
        fallbackLanguage: "en"
      )
    )
    // Makes plain Text("key") and NSLocalizedString resolve through Translation Hosting first.
    SimpleLocalize.enableBundleIntegration()
  }

  var body: some Scene {
    WindowGroup {
      ContentView()
    }
  }
}
