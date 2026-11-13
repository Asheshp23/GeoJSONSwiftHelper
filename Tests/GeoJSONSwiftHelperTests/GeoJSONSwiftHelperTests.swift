import Testing
import CoreLocation
import MapKit
import Turf
@testable import GeoJSONSwiftHelper

// MARK: - Helpers

/// Builds a GeoJSON Polygon geometry string for an axis-aligned box.
private func boxGeometry(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) -> String {
  """
  {"type":"Polygon","coordinates":[[[\(minLon),\(minLat)],[\(maxLon),\(minLat)],[\(maxLon),\(maxLat)],[\(minLon),\(maxLat)],[\(minLon),\(minLat)]]]}
  """
}

private func boxFeature(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) -> String {
  #"{"type":"Feature","properties":{},"geometry":"# + boxGeometry(minLon: minLon, minLat: minLat, maxLon: maxLon, maxLat: maxLat) + "}"
}

private func featureCollection(_ features: [String]) -> String {
  #"{"type":"FeatureCollection","features":["# + features.joined(separator: ",") + "]}"
}

private func object(_ json: String) throws -> GeoJSONObject {
  try #require(GeoJSONObject.create(from: json))
}

private func gridCell(minLon: Double, minLat: Double, maxLon: Double, maxLat: Double) -> GridHelper.GridPolygonOverlay {
  let cell = GridHelper.GridPolygonOverlay()
  cell.boundary = Turf.MultiPolygon([Turf.Polygon([[
    CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
    CLLocationCoordinate2D(latitude: minLat, longitude: maxLon),
    CLLocationCoordinate2D(latitude: maxLat, longitude: maxLon),
    CLLocationCoordinate2D(latitude: maxLat, longitude: minLon),
    CLLocationCoordinate2D(latitude: minLat, longitude: minLon),
  ]])])
  return cell
}

private let nullGeometryFeature = #"{"type":"Feature","properties":{},"geometry":null}"#

// MARK: - Bounds & center

@Suite("Bounds")
struct BoundsTests {
  struct Case: CustomTestStringConvertible, Sendable {
    let name: String
    let minLon, minLat, maxLon, maxLat: Double
    var testDescription: String { name }
  }

  @Test("Bounds match the input box in every hemisphere", arguments: [
    Case(name: "north-east", minLon: 10, minLat: 40, maxLon: 11, maxLat: 41),
    Case(name: "south-west", minLon: -58.5, minLat: -34.7, maxLon: -58.3, maxLat: -34.5),
    Case(name: "south-east", minLon: 150.1, minLat: -33.9, maxLon: 150.2, maxLat: -33.8),
    Case(name: "north-west", minLon: -97.2, minLat: 49.8, maxLon: -97.1, maxLat: 49.9),
    Case(name: "crosses equator", minLon: 30, minLat: -0.5, maxLon: 31, maxLat: 0.5),
    Case(name: "crosses prime meridian", minLon: -0.5, minLat: 51, maxLon: 0.5, maxLat: 52),
    Case(name: "crosses both", minLon: -1, minLat: -1, maxLon: 1, maxLat: 1),
    Case(name: "touches lat 0 from south", minLon: 5, minLat: -2, maxLon: 6, maxLat: 0),
    Case(name: "touches lon 0 from west", minLon: -2, minLat: 5, maxLon: 0, maxLat: 6),
    Case(name: "corner at origin", minLon: 0, minLat: 0, maxLon: 1, maxLat: 1),
  ])
  func boundsMatchBox(_ c: Case) throws {
    let geo = try object(boxGeometry(minLon: c.minLon, minLat: c.minLat, maxLon: c.maxLon, maxLat: c.maxLat))
    let bounds = try #require(geo.bounds)

    #expect(bounds.southwest.latitude == c.minLat)
    #expect(bounds.southwest.longitude == c.minLon)
    #expect(bounds.northeast.latitude == c.maxLat)
    #expect(bounds.northeast.longitude == c.maxLon)

    let center = try #require(geo.center)
    #expect(center.latitude == (c.minLat + c.maxLat) / 2)
    #expect(center.longitude == (c.minLon + c.maxLon) / 2)
  }

  @Test func boundsSpanAllFeaturesInCollection() throws {
    let geo = try object(featureCollection([
      boxFeature(minLon: -3, minLat: -2, maxLon: -1, maxLat: -1),
      boxFeature(minLon: 1, minLat: 1, maxLon: 4, maxLat: 5),
    ]))
    let bounds = try #require(geo.bounds)
    #expect(bounds.southwest.latitude == -2)
    #expect(bounds.southwest.longitude == -3)
    #expect(bounds.northeast.latitude == 5)
    #expect(bounds.northeast.longitude == 4)
  }

  @Test func emptyGeometryHasNoBoundsOrCenter() throws {
    let geo = try object(nullGeometryFeature)
    #expect(geo.bounds == nil)
    #expect(geo.center == nil)
    #expect(geo.region == nil)
  }
}

// MARK: - Coordinates with null geometry

@Suite("Null geometry")
struct NullGeometryTests {
  @Test func featureWithNullGeometryHasNoCoordinates() throws {
    let geo = try object(nullGeometryFeature)
    #expect(geo.coordinates.isEmpty)
  }

  @Test func collectionSkipsNullGeometryFeatures() throws {
    let geo = try object(featureCollection([
      nullGeometryFeature,
      boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1),
      nullGeometryFeature,
    ]))
    #expect(geo.coordinates.count == 5)
    #expect(geo.bounds != nil)
  }
}

// MARK: - Comparable

@Suite("CLLocationCoordinate2D ordering")
struct CoordinateOrderingTests {
  private func c(_ lat: Double, _ lon: Double) -> CLLocationCoordinate2D {
    CLLocationCoordinate2D(latitude: lat, longitude: lon)
  }

  @Test func isLexicographic() {
    #expect(c(0, 5) < c(1, 0))   // latitude decides first
    #expect(c(1, 0) < c(1, 5))   // longitude breaks ties
    #expect(!(c(1, 5) < c(1, 0)))
    #expect(!(c(1, 1) < c(1, 1))) // irreflexive
  }

  @Test func incomparabilityIsTransitive() {
    // With the old '&&' ordering, a~b and b~c but a < c.
    let a = c(0, 0), b = c(1, -1), cc = c(2, 2)
    let incomparable = { (x: CLLocationCoordinate2D, y: CLLocationCoordinate2D) in !(x < y) && !(y < x) }
    #expect(!(incomparable(a, b) && incomparable(b, cc) && !incomparable(a, cc)))
  }

  @Test func sortIsDeterministic() {
    let coords = [c(1, 2), c(-1, 3), c(1, -2), c(0, 0), c(-1, -3)]
    let sorted = coords.sorted()
    #expect(sorted == [c(-1, -3), c(-1, 3), c(0, 0), c(1, -2), c(1, 2)])
    #expect(coords.reversed().sorted() == sorted)
  }
}

// MARK: - GeoJSONSourceData

@Suite("GeoJSONSourceData equality")
struct SourceDataEqualityTests {
  @Test func identicalGeometriesAreEqual() throws {
    let a = try object(boxGeometry(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)).sourceData
    let b = try object(boxGeometry(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)).sourceData
    #expect(a == b)
  }

  @Test func identicalFeatureCollectionsAreEqual() throws {
    let json = featureCollection([boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)])
    #expect(try object(json).sourceData == object(json).sourceData)
  }

  @Test func emptyEqualsEmpty() {
    #expect(GeoJSONSourceData.empty == .empty)
  }

  @Test func differentValuesAreNotEqual() throws {
    let a = try object(boxGeometry(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)).sourceData
    let b = try object(boxGeometry(minLon: 0, minLat: 0, maxLon: 2, maxLat: 1)).sourceData
    let fc = try object(featureCollection([boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)])).sourceData
    #expect(a != b)
    #expect(a != fc)
    #expect(a != .empty)
  }
}

// MARK: - SwiftUI map content

@Suite("Map content")
struct MapContentTests {
  @Test func polygonHolesArePreserved() throws {
    let json = """
    {"type":"Polygon","coordinates":[
      [[0,0],[4,0],[4,4],[0,4],[0,0]],
      [[1,1],[2,1],[2,2],[1,2],[1,1]]
    ]}
    """
    let polygon = try #require(object(json).polygons?.first)
    let mkPolygon = polygon.mkPolygon
    #expect(mkPolygon.pointCount == 5)
    #expect(mkPolygon.interiorPolygons?.count == 1)
  }
}

// MARK: - Grid

@Suite("Grid intersection")
struct GridIntersectionTests {
  @Test func cellSpanningTwoDisjointFeaturesKeepsBothParts() throws {
    let boundary = featureCollection([
      boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1),
      boxFeature(minLon: 2, minLat: 0, maxLon: 3, maxLat: 1),
    ])
    let cell = gridCell(minLon: 0.5, minLat: 0, maxLon: 2.5, maxLat: 1)

    let clipped = try #require(cell.intersection(with: boundary))
    let polygons = try #require(clipped.boundary?.polygons)
    #expect(polygons.count == 2)

    let multiPolygon = try #require(clipped.boundary)
    let bounds = try #require(GeoJSONObject.geometry(.multiPolygon(multiPolygon)).bounds)
    #expect(abs(bounds.southwest.longitude - 0.5) < 1e-9)
    #expect(abs(bounds.northeast.longitude - 2.5) < 1e-9)
  }

  @Test func cellSpanningAdjacentFeaturesIsUnioned() throws {
    let boundary = featureCollection([
      boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1),
      boxFeature(minLon: 1, minLat: 0, maxLon: 2, maxLat: 1),
    ])
    let cell = gridCell(minLon: 0.5, minLat: 0.25, maxLon: 1.5, maxLat: 0.75)

    let clipped = try #require(cell.intersection(with: boundary))
    let polygons = try #require(clipped.boundary?.polygons)
    #expect(polygons.count == 1)
    let area = try #require(polygons.first?.area)
    let expected = try #require(gridCell(minLon: 0.5, minLat: 0.25, maxLon: 1.5, maxLat: 0.75).boundary?.polygons.first?.area)
    #expect(abs(area - expected) / expected < 1e-6)
  }

  @Test func cellOutsideBoundaryReturnsNil() {
    let boundary = boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)
    let cell = gridCell(minLon: 5, minLat: 5, maxLon: 6, maxLat: 6)
    #expect(cell.intersection(with: boundary) == nil)
  }

  @Test func clippedCellIsSelected() throws {
    let boundary = boxFeature(minLon: 0, minLat: 0, maxLon: 1, maxLat: 1)
    let cell = gridCell(minLon: 0.5, minLat: 0.5, maxLon: 1.5, maxLat: 1.5)
    let clipped = try #require(cell.intersection(with: boundary))
    #expect(clipped.selected)
  }
}

@Suite("Grid polygons")
struct GridPolygonTests {
  @Test("Cells are closed squares of the requested size", arguments: [0.0, 30.0])
  func cellsAreSquares(rotation: Double) throws {
    let field = try object(boxGeometry(minLon: -0.002, minLat: -0.001, maxLon: 0.002, maxLat: 0.001))
    let bounds = try #require(field.bounds)
    let center = try #require(field.center)
    let cellSize = 20.0

    let cells = GridHelper.calcGridPolygons(bounds: bounds,
                                            center: center,
                                            rotation: rotation,
                                            offset: SizeInMeters(width: 0, height: 0),
                                            gridCellSize: cellSize)
    #expect(!cells.isEmpty)

    for cell in cells {
      let ring = try #require(cell.boundary?.polygons.first?.outerRing.coordinates)
      #expect(ring.count == 5)
      #expect(ring.first == ring.last)
      for (a, b) in zip(ring, ring.dropFirst()) {
        #expect(abs(a.distance(from: b) - cellSize) < cellSize * 0.01)
      }
    }
  }

  @Test func gridCoversField() throws {
    let fieldJSON = boxFeature(minLon: -0.002, minLat: -0.001, maxLon: 0.002, maxLat: 0.001)
    let field = try object(fieldJSON)
    let bounds = try #require(field.bounds)
    let center = try #require(field.center)
    let cells = GridHelper.calcGridPolygons(bounds: bounds,
                                            center: center,
                                            rotation: 15,
                                            offset: SizeInMeters(width: 3, height: -4),
                                            gridCellSize: 25)
    let clippedArea = cells
      .compactMap { $0.intersection(with: fieldJSON) }
      .compactMap { $0.boundary?.polygons }
      .flatMap { $0 }
      .reduce(0) { $0 + $1.area }
    let fieldArea = try #require(field.polygons?.first?.area)
    #expect(abs(clippedArea - fieldArea) / fieldArea < 0.001)
  }
}
