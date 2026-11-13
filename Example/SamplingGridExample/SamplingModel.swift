import Foundation
import Observation
import CoreLocation
import Turf
import GeoJSONSwiftHelper

/// Field status of a single sampling cell. Tapping a cell cycles pending → done → skipped.
enum SampleStatus: String, CaseIterable, Identifiable {
  case pending, done, skipped

  var id: Self { self }

  var next: SampleStatus {
    switch self {
    case .pending: .done
    case .done: .skipped
    case .skipped: .pending
    }
  }
}

/// Which cells to include when exporting.
enum ExportFilter: String, CaseIterable, Identifiable {
  case done = "Done"
  case skipped = "Skipped"
  case all = "All"

  var id: Self { self }

  func includes(_ status: SampleStatus) -> Bool {
    switch self {
    case .done: status == .done
    case .skipped: status == .skipped
    case .all: true
    }
  }
}

struct GridParameters: Equatable {
  var cellSize: Double = 30
  var rotation: Double = 0
  var offsetX: Double = 0
  var offsetY: Double = 0
}

/// A grid cell already clipped to the field boundary.
struct SampleCell: Identifiable {
  let id: Int
  let shape: Turf.MultiPolygon
  var status: SampleStatus = .pending

  func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
    shape.polygons.contains { $0.contains(coordinate) }
  }
}

@MainActor
@Observable
final class SamplingModel {
  let boundary: GeoJSONObject
  private let boundaryJSON: String

  var parameters = GridParameters()
  private(set) var cells: [SampleCell] = []

  init(boundaryJSON: String) throws {
    guard let boundary = GeoJSONObject.create(from: boundaryJSON) else {
      throw CocoaError(.fileReadCorruptFile)
    }
    self.boundary = boundary
    self.boundaryJSON = boundaryJSON
  }

  /// Loads the bundled, invented sample field.
  static func loadSample() throws -> SamplingModel {
    guard let url = Bundle.main.url(forResource: "sample-field", withExtension: "geojson") else {
      throw CocoaError(.fileNoSuchFile)
    }
    return try SamplingModel(boundaryJSON: String(contentsOf: url, encoding: .utf8))
  }

  /// Rebuilds the rotated grid and clips every cell to the field boundary.
  /// Cell statuses reset because the cells themselves change.
  func regenerateGrid() {
    guard let bounds = boundary.bounds, let center = boundary.center else {
      cells = []
      return
    }

    let grid = GridHelper.calcGridPolygons(
      bounds: bounds,
      center: center,
      rotation: parameters.rotation,
      offset: SizeInMeters(width: parameters.offsetX, height: parameters.offsetY),
      gridCellSize: parameters.cellSize)

    cells = grid
      .compactMap { $0.intersection(with: boundaryJSON)?.boundary }
      .enumerated()
      .map { SampleCell(id: $0.offset, shape: $0.element) }
  }

  func cycleStatus(at coordinate: CLLocationCoordinate2D) {
    guard let index = cells.firstIndex(where: { $0.contains(coordinate) }) else { return }
    cells[index].status = cells[index].status.next
  }

  func count(of status: SampleStatus) -> Int {
    cells.count(where: { $0.status == status })
  }

  func exportCount(_ filter: ExportFilter) -> Int {
    cells.count(where: { filter.includes($0.status) })
  }

  /// Encodes the cells matching `filter` as a GeoJSON FeatureCollection.
  func exportData(_ filter: ExportFilter) throws -> Data {
    let features = cells
      .filter { filter.includes($0.status) }
      .map { cell in
        var feature = Turf.Feature(geometry: .multiPolygon(cell.shape))
        feature.properties = [
          "id": .number(Double(cell.id)),
          "status": .string(cell.status.rawValue),
          "cellSizeMeters": .number(parameters.cellSize),
          "rotationDegrees": .number(parameters.rotation),
        ]
        return feature
      }

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(Turf.FeatureCollection(features: features))
  }
}
