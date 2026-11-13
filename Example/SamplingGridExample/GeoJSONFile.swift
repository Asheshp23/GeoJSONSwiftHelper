import SwiftUI
import UniformTypeIdentifiers

/// Exported cells, shared as a `.geojson` file.
struct GeoJSONFile: Transferable {
  let data: Data

  static var transferRepresentation: some TransferRepresentation {
    DataRepresentation(exportedContentType: .json) { $0.data }
      .suggestedFileName("sampling-cells.geojson")
  }
}
