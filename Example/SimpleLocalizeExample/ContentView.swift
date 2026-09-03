import SwiftUI
import SimpleLocalizeOTA

struct ContentView: View {

  @StateObject private var localization = SimpleLocalizeObservable()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      Text(simpleLocalized: "home.title")
        .font(.largeTitle.bold())

      Text(simpleLocalized: "home.subtitle")
        .font(.body)
        .foregroundStyle(.secondary)

      Text(simpleLocalized: "home.greeting")
        .font(.body)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

      Text(simpleLocalized: "home.language")
        .font(.subheadline.weight(.medium))
      Picker(selection: languageBinding) {
        ForEach(["en", "pl", "de"], id: \.self) { Text($0).tag($0) }
      } label: {
        EmptyView()
      }
      .pickerStyle(.segmented)

      Button {
        SimpleLocalize.shared.refresh()
      } label: {
        Text(simpleLocalized: "home.cta").frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)

      Text(status)
        .font(.footnote)
        .foregroundStyle(.secondary)

      Spacer()
    }
    .padding(24)
    .simpleLocalizeAware()
  }

  private var languageBinding: Binding<String> {
    Binding(
      get: { localization.currentLanguage ?? "en" },
      set: { localization.setLanguage($0) }
    )
  }

  private var status: String {
    if projectToken == "YOUR_PROJECT_TOKEN" {
      return "No project token set - showing strings bundled in the app. Add yours in ExampleApp.swift."
    }
    guard let language = localization.currentLanguage else {
      return "Downloading translations..."
    }
    return "\(SimpleLocalize.shared.allTranslations().count) keys downloaded, language: \(language)"
  }
}
