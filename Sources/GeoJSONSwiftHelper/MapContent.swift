import SwiftUI
import MapKit
import Turf

// MARK: - SwiftUI Map primitives from Turf geometries

extension MapPolygon {
  /// Creates a SwiftUI map polygon from a Turf polygon, preserving inner rings as holes.
  public init(_ polygon: Turf.Polygon) {
    // Routing through MKPolygon keeps interior polygons, which
    // `MapPolygon(coordinates:)` can't express.
    self.init(polygon.mkPolygon)
  }
}

extension MapPolyline {
  /// Creates a SwiftUI map polyline from a Turf line string.
  public init(_ lineString: Turf.LineString, contourStyle: MapPolyline.ContourStyle = .straight) {
    self.init(coordinates: lineString.coordinates, contourStyle: contourStyle)
  }
}

extension Turf.Polygon {
  var mkPolygon: MKPolygon {
    let interiorPolygons = innerRings.map {
      MKPolygon(coordinates: $0.coordinates, count: $0.coordinates.count)
    }
    return MKPolygon(coordinates: outerRing.coordinates,
                     count: outerRing.coordinates.count,
                     interiorPolygons: interiorPolygons)
  }
}

// MARK: - GeoJSON map content

/// Renders every geometry in a GeoJSON object inside a SwiftUI `Map`:
/// polygons as `MapPolygon`, line strings as `MapPolyline`, and points as `MapCircle`.
///
/// ```swift
/// Map {
///   GeoJSONMapContent(fieldBoundary)
/// }
/// ```
public struct GeoJSONMapContent: MapContent {
  private let polygons: [Turf.Polygon]
  private let lineStrings: [Turf.LineString]
  private let points: [CLLocationCoordinate2D]

  private let fill: Color
  private let stroke: Color
  private let lineWidth: CGFloat
  private let pointRadius: CLLocationDistance

  public init(_ object: GeoJSONObject,
              fill: Color = .blue.opacity(0.25),
              stroke: Color = .blue,
              lineWidth: CGFloat = 2,
              pointRadius: CLLocationDistance = 1) {
    let geometries = object.features.compactMap(\.geometry)
    self.init(geometries: geometries, fill: fill, stroke: stroke, lineWidth: lineWidth, pointRadius: pointRadius)
  }

  public init(_ geometry: Turf.Geometry,
              fill: Color = .blue.opacity(0.25),
              stroke: Color = .blue,
              lineWidth: CGFloat = 2,
              pointRadius: CLLocationDistance = 1) {
    self.init(geometries: [geometry], fill: fill, stroke: stroke, lineWidth: lineWidth, pointRadius: pointRadius)
  }

  /// Convenience for grid cells, whose `boundary` is a `MultiPolygon`.
  public init(_ multiPolygon: Turf.MultiPolygon,
              fill: Color = .blue.opacity(0.25),
              stroke: Color = .blue,
              lineWidth: CGFloat = 2) {
    self.init(geometries: [.multiPolygon(multiPolygon)], fill: fill, stroke: stroke, lineWidth: lineWidth, pointRadius: 1)
  }

  private init(geometries: [Turf.Geometry],
               fill: Color,
               stroke: Color,
               lineWidth: CGFloat,
               pointRadius: CLLocationDistance) {
    var polygons: [Turf.Polygon] = []
    var lineStrings: [Turf.LineString] = []
    var points: [CLLocationCoordinate2D] = []
    geometries.forEach { Self.flatten($0, into: &polygons, &lineStrings, &points) }

    self.polygons = polygons
    self.lineStrings = lineStrings
    self.points = points
    self.fill = fill
    self.stroke = stroke
    self.lineWidth = lineWidth
    self.pointRadius = pointRadius
  }

  public var body: some MapContent {
    ForEach(polygons.indices, id: \.self) { index in
      MapPolygon(polygons[index])
        .foregroundStyle(fill)
        .stroke(stroke, lineWidth: lineWidth)
    }
    ForEach(lineStrings.indices, id: \.self) { index in
      MapPolyline(lineStrings[index])
        .stroke(stroke, lineWidth: lineWidth)
    }
    ForEach(points.indices, id: \.self) { index in
      MapCircle(center: points[index], radius: pointRadius)
        .foregroundStyle(stroke)
    }
  }

  /// Splits a (possibly nested) geometry into the three primitive kinds `Map` can draw.
  private static func flatten(_ geometry: Turf.Geometry,
                              into polygons: inout [Turf.Polygon],
                              _ lineStrings: inout [Turf.LineString],
                              _ points: inout [CLLocationCoordinate2D]) {
    switch geometry {
    case .point(let point):
      points.append(point.coordinates)
    case .multiPoint(let multiPoint):
      points.append(contentsOf: multiPoint.coordinates)
    case .lineString(let lineString):
      lineStrings.append(lineString)
    case .multiLineString(let multiLineString):
      lineStrings.append(contentsOf: multiLineString.coordinates.map { Turf.LineString($0) })
    case .polygon(let polygon):
      polygons.append(polygon)
    case .multiPolygon(let multiPolygon):
      polygons.append(contentsOf: multiPolygon.polygons)
    case .geometryCollection(let collection):
      collection.geometries.forEach { flatten($0, into: &polygons, &lineStrings, &points) }
    @unknown default:
      break
    }
  }
}
