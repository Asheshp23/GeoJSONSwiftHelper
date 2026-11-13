import SwiftUI

@main
struct SamplingGridExampleApp: App {
  @State private var model = try? SamplingModel.loadSample()

  var body: some Scene {
    WindowGroup {
      if let model {
        ContentView(model: model)
      } else {
        ContentUnavailableView("Sample field missing",
                               systemImage: "map",
                               description: Text("sample-field.geojson could not be loaded."))
      }
    }
  }
}
