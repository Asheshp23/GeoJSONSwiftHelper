import Foundation
import CoreLocation
import Turf
import MapKit

extension GeoJSONObject {
  public static func create(from geoJSONString: String) -> GeoJSONObject? {
    guard let data = geoJSONString.data(using: .utf8) else { return nil }

    do {
      return try JSONDecoder().decode(GeoJSONObject.self, from: data)
    } catch {
      print("Error while decoding geoJSONObject...")
      print(String(describing: error))
    }

    return nil
  }

  public var coordinates: [CLLocationCoordinate2D] {
    switch self {
    case .geometry(let geometry):
      return getCoordinates(from: geometry)
    // Features may have null geometry; they contribute no coordinates.
    case .feature(let feature):
      return feature.geometry.map(getCoordinates(from:)) ?? []
    case .featureCollection(let featureCollection):
      return featureCollection.features.flatMap { $0.geometry.map(getCoordinates(from:)) ?? [] }
    }
  }

  private func getCoordinates(from geometry: Turf.Geometry) -> [CLLocationCoordinate2D] {
    switch geometry {
    case .point(let point):
      return [point.coordinates]
    case .lineString(let lineString):
      return lineString.coordinates
    case .polygon(let polygon):
      return polygon.coordinates.flatMap {$0}
    case .multiPoint(let multiPoint):
      return multiPoint.coordinates
    case .multiLineString(let multiLineString):
      return multiLineString.coordinates.flatMap {$0}
    case .multiPolygon(let multiPolygon):
      return multiPolygon.coordinates.flatMap {$0}.flatMap {$0}
    case .geometryCollection(let geometryCollection):
      return geometryCollection.geometries.flatMap { getCoordinates(from: $0 )}
    }
  }

  public var polygons: [Turf.Polygon]? {
    switch self {
    case .geometry(let geometry):
      return geometry.polygons
    case .feature(let feature):
      return feature.geometry?.polygons
    case .featureCollection(let featureCollection):
      return featureCollection.features.compactMap { $0.geometry?.polygons }.flatMap { $0 }
    }
  }

  public var features: [Turf.Feature] {
    switch self {
    case .geometry(let geometry):
      return [Turf.Feature(geometry: geometry)]
    case .feature(let feature):
      return [feature]
    case .featureCollection(let featureCollection):
      return featureCollection.features
    }
  }

  public var multiPolygon: Turf.MultiPolygon? {
    switch self {
    case .geometry(let geometry):
      return geometry.multiPolygon
    case .feature(let feature):
      return feature.geometry?.multiPolygon
    case .featureCollection(let featureCollection):
      let polygons = featureCollection.features.compactMap { $0.geometry?.polygons }
      if !polygons.isEmpty {
        return Turf.MultiPolygon(polygons.flatMap { $0 })
      }
      return nil
    }
  }

  public var center: CLLocationCoordinate2D {
    var maxLatitude: Double = -200
    var maxLongitude: Double = -200
    var minLatitude: Double = Double(MAXFLOAT)
    var minLongitude: Double = Double(MAXFLOAT)

    for location in self.coordinates {
      if location.latitude < minLatitude {
        minLatitude = location.latitude
      }

      if location.longitude < minLongitude {
        minLongitude = location.longitude
      }

      if location.latitude > maxLatitude {
        maxLatitude = location.latitude
      }

      if location.longitude > maxLongitude {
        maxLongitude = location.longitude
      }
    }

    return CLLocationCoordinate2DMake(
      CLLocationDegrees((maxLatitude + minLatitude) * 0.5),
      CLLocationDegrees((maxLongitude + minLongitude) * 0.5))
  }

  /// The axis-aligned bounding box of all coordinates, or `nil` if there are none
  /// (e.g. a feature with null geometry).
  public var bounds: CoordinateBounds? {
    var minLatitude: CLLocationDegrees?
    var maxLatitude: CLLocationDegrees?
    var minLongitude: CLLocationDegrees?
    var maxLongitude: CLLocationDegrees?

    for coordinate in coordinates {
      minLatitude = min(minLatitude ?? coordinate.latitude, coordinate.latitude)
      maxLatitude = max(maxLatitude ?? coordinate.latitude, coordinate.latitude)
      minLongitude = min(minLongitude ?? coordinate.longitude, coordinate.longitude)
      maxLongitude = max(maxLongitude ?? coordinate.longitude, coordinate.longitude)
    }

    guard let minLatitude, let maxLatitude, let minLongitude, let maxLongitude else { return nil }

    return CoordinateBounds(
      southwest: CLLocationCoordinate2D(latitude: minLatitude, longitude: minLongitude),
      northeast: CLLocationCoordinate2D(latitude: maxLatitude, longitude: maxLongitude))
  }

  private func bounds(topOffset: Double,
                      bottomOffset: Double,
                      leftoffset: Double,
                      rightOffset: Double) -> CoordinateBounds? {
    guard let bounds else { return nil }

    let maxNE = bounds.northeast
      .movedBy(latitudinalMeters: topOffset,
               longitudinalMeters: leftoffset)
    let maxSW = bounds.southwest
      .movedBy(latitudinalMeters: bottomOffset,
               longitudinalMeters: rightOffset)
    return CoordinateBounds(southwest: maxSW,
                            northeast: maxNE)
  }

  public func region(topOffset: Double,
                     bottomOffset: Double,
                     leftoffset: Double,
                     rightOffset: Double) -> MKCoordinateRegion? {
    guard let boundsWithOffset = bounds(topOffset: topOffset,
                                        bottomOffset: bottomOffset,
                                        leftoffset: leftoffset,
                                        rightOffset: rightOffset) else { return nil }

    return MKCoordinateRegion(coordinates: [boundsWithOffset.northeast, boundsWithOffset.southwest])
  }

  public var region: MKCoordinateRegion? {
    guard let bounds else { return nil }
    return MKCoordinateRegion(coordinates: [bounds.northeast, bounds.southwest])
    // This is too snug
    // return MKCoordinateRegion(coordinates: coordinates)
  }

  public var mapPolygons: [MKPolygon]? {
    return overlays?.filter { overlay in
      overlay is MKPolygon
    } as? [MKPolygon]
  }

  public var overlays: [MKOverlay]? {
    switch self {
    case .geometry(let geometry):
      return  geometry.overlays
    case .feature(let feature):
      return feature.geometry?.overlays
    case .featureCollection(let featureCollection):
      return featureCollection.features.compactMap { $0.geometry?.overlays }.flatMap({ $0 })
    }
  }

  var sourceData: GeoJSONSourceData {
    switch self {
    case .geometry(let geometry):
      return .geometry(geometry)
    case .feature(let feature):
      return .feature(feature)
    case .featureCollection(let featureCollection):
      return .featureCollection(featureCollection)
    }
  }
}

public struct CoordinateBounds {
  public let southwest: CLLocationCoordinate2D
  public let northeast: CLLocationCoordinate2D

  public var southeast: CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: southwest.latitude, longitude: northeast.longitude)
  }
  public var northwest: CLLocationCoordinate2D {
    return CLLocationCoordinate2D(latitude: northeast.latitude, longitude: southwest.longitude)
  }
}

/// Captures potential values of the `data` property of a GeoJSONSource
public enum GeoJSONSourceData: Codable {
  /// The `data` property can be a url
  case url(URL)

  /// The `data` property can be a feature
  case feature(Feature)

  /// The `data` property can be a feature collection
  case featureCollection(FeatureCollection)

  /// The `data` property can be a geometry with no associated properties.
  case geometry(Geometry)

  /// Empty data to be used for initialization
  case empty

  public init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let decodedURL = try? container.decode(URL.self) {
      self = .url(decodedURL)
      return
    }

    if let decodedFeature = try? container.decode(Feature.self) {
      self = .feature(decodedFeature)
      return
    }

    if let decodedFeatureCollection = try? container.decode(FeatureCollection.self) {
      self = .featureCollection(decodedFeatureCollection)
      return
    }

    if let decodedString = try? container.decode(String.self), decodedString.isEmpty {
      self = .empty
      return
    }

    let context = DecodingError.Context(codingPath: decoder.codingPath,
                                        debugDescription: "Failed to decode GeoJSONSource `data` property")
    throw DecodingError.dataCorrupted(context)
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()

    switch self {
    case .url(let url):
      try container.encode(url)
    case .feature(let feature):
      try container.encode(feature)
    case .featureCollection(let featureCollection):
      try container.encode(featureCollection)
    case .geometry(let geometry):
      try container.encode(geometry)
    case .empty:
      try container.encode("")
    }
  }
}

extension GeoJSONSourceData: Equatable {
  public static func == (lhs: GeoJSONSourceData, rhs: GeoJSONSourceData) -> Bool {
    switch (lhs, rhs) {
    case (let .url(lhsURL), let .url(rhsURL)):
      return lhsURL == rhsURL
    case (let .feature(lhsFeature), let .feature(rhsFeature)):
      return lhsFeature == rhsFeature
    default:
      return false
    }
  }
}

extension MKCoordinateRegion {
  init?(coordinates: [CLLocationCoordinate2D]) {
    // first create a region centered around the prime meridian
    let primeRegion = MKCoordinateRegion.region(for: coordinates, transform: { $0 }, inverseTransform: { $0 })

    // next create a region centered around the 180th meridian
    let transformedRegion = MKCoordinateRegion.region(for: coordinates, transform: MKCoordinateRegion.transform, inverseTransform: MKCoordinateRegion.inverseTransform)

    // return the region that has the smallest longitude delta
    if let a = primeRegion, let b = transformedRegion,
       let min = [a, b].min(by: { $0.span.longitudeDelta < $1.span.longitudeDelta }) {
      self = min
    } else if let a = primeRegion {
      self = a
    } else if let b = transformedRegion {
      self = b
    } else {
      return nil
    }
  }

  // Latitude -180...180 -> 0...360
  private static func transform(c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    if c.longitude < 0 { return CLLocationCoordinate2DMake(c.latitude, 360 + c.longitude) }
    return c
  }

  // Latitude 0...360 -> -180...180
  private static func inverseTransform(c: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
    if c.longitude > 180 { return CLLocationCoordinate2DMake(c.latitude, -360 + c.longitude) }
    return c
  }

  private typealias Transform = (CLLocationCoordinate2D) -> (CLLocationCoordinate2D)

  private static func region(for coordinates: [CLLocationCoordinate2D], transform: Transform, inverseTransform: Transform) -> MKCoordinateRegion? {
    // handle empty array
    guard !coordinates.isEmpty else { return nil }

    // handle single coordinate
    guard coordinates.count > 1 else {
      return MKCoordinateRegion(center: coordinates[0], span: MKCoordinateSpan(latitudeDelta: 1, longitudeDelta: 1))
    }

    let transformed = coordinates.map(transform)

    // find the span
    let minLat = transformed.min { $0.latitude < $1.latitude }!.latitude
    let maxLat = transformed.max { $0.latitude < $1.latitude }!.latitude
    let minLon = transformed.min { $0.longitude < $1.longitude }!.longitude
    let maxLon = transformed.max { $0.longitude < $1.longitude }!.longitude
    let span = MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon)

    // find the center of the span
    let center = inverseTransform(CLLocationCoordinate2DMake((maxLat - span.latitudeDelta / 2), maxLon - span.longitudeDelta / 2))

    return MKCoordinateRegion(center: center, span: span)
  }
}

extension CLLocationCoordinate2D {
  public func distance(from otherCoordinate: CLLocationCoordinate2D) -> Double {
    let myLoc = CLLocation(latitude: self.latitude, longitude: self.longitude)
    let otherLoc = CLLocation(latitude: otherCoordinate.latitude, longitude: otherCoordinate.longitude)

    return myLoc.distance(from: otherLoc)
  }
}

extension Turf.Feature {
  public func contains(_ coordinate: LocationCoordinate2D, ignoreBoundary: Bool = false) -> Bool {
    if let polygons: [Turf.Polygon] = geometry?.polygons {
      for polygon in polygons {
        if polygon.outerRing.contains(coordinate) && !polygon.innerRings.contains(where: { $0.contains(coordinate)}) {
          return true
        }
      }
    }

    return false
  }

  public var overlays: [MKOverlay]? {
    return geometry?.overlays
  }
}

extension Turf.Geometry {
  var multiPolygon: Turf.MultiPolygon? {
    switch self {
    case .polygon(let polygon):
      return Turf.MultiPolygon([polygon])
    case .multiPolygon(let multiPolygon):
      return multiPolygon
    case .geometryCollection(let geometryCollection):
      let polygons = geometryCollection.geometries.compactMap { $0.polygons }
      return Turf.MultiPolygon(polygons.flatMap { $0 })
    default:
      return nil
    }
  }

  var overlays: [MKOverlay] {
    switch self {
    case .point(let point):
      return [point.overlay]
    case .lineString(let lineString):
      return [lineString.overlay]
    case .polygon(let polygon):
      return [polygon.overlay]
    case .multiPoint(let multiPoint):
      return multiPoint.overlays
    case .multiLineString(let multiLineString):
      return multiLineString.overlays
    case .multiPolygon(let multiPolygon):
      return multiPolygon.overlays
    case .geometryCollection(let geometryCollection):
      return geometryCollection.geometries.flatMap { $0.geometry.overlays }
    }
  }

  var polygons: [Turf.Polygon]? {
    switch self {
    case .polygon(let polygon):
      return [polygon]
    case .multiPolygon(let multiPolygon):
      return multiPolygon.polygons
    case .geometryCollection(let geometryCollection):
      return geometryCollection.geometries.compactMap { $0.polygons }.flatMap({ $0 })
    default:
      return nil
    }
  }
}

extension Turf.Point {
  var overlay: MKOverlay {
    MKCircle(center: self.coordinates,radius: 1.0)
  }
}

extension Turf.LineString {
  var overlay: MKOverlay {
    MKPolyline(coordinates: self.coordinates, count: self.coordinates.count)
  }
}

extension Turf.MultiPoint {
  var overlays: [MKOverlay] {
    self.coordinates.map { MKCircle(center: $0, radius: 1.0) }
  }
}

extension Turf.MultiLineString {
  var overlays: [MKOverlay] {
    self.coordinates
      .flatMap { [MKPolyline(coordinates: $0, count: $0.count)] }
  }
}

extension Turf.Polygon {
  var overlay: MKOverlay {
    let interiorOverlays = self.innerRings.map({
      MKPolygon(coordinates: $0.coordinates, count: $0.coordinates.count)
    })
    let overlay = MKPolygon(
      coordinates: self.outerRing.coordinates,
      count: self.outerRing.coordinates.count,
      interiorPolygons: interiorOverlays)
    return overlay
  }
}

extension Turf.MultiPolygon {
  var overlays: [MKOverlay] {
    self.polygons.map({ $0.overlay })
  }
}
