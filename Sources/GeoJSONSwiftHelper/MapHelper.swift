import MapKit
import Turf

extension CLLocationCoordinate2D {
  public func movedBy(latitudinalMeters: CLLocationDistance, longitudinalMeters: CLLocationDistance) -> CLLocationCoordinate2D {
    let region = MKCoordinateRegion(center: self, latitudinalMeters: abs(latitudinalMeters), longitudinalMeters: abs(longitudinalMeters))
    
    let latitudeDelta = region.span.latitudeDelta
    let longitudeDelta = region.span.longitudeDelta
    
    let latitudialSign = CLLocationDistance(latitudinalMeters.sign == .minus ? -1 : 1)
    let longitudialSign = CLLocationDistance(longitudinalMeters.sign == .minus ? -1 : 1)
    
    let newLatitude = latitude + latitudialSign * latitudeDelta
    let newLongitude = longitude + longitudialSign * longitudeDelta
    
    let newCoordinate = CLLocationCoordinate2D(latitude: newLatitude, longitude: newLongitude)
    
    return newCoordinate
  }
  
  public func movedBy(distanceMeters: Double, bearingRadians: Double) -> CLLocationCoordinate2D {
    let distRadians = distanceMeters / (6372797.6) // earth radius in meters
    
    let lat1 = self.latitude * Double.pi / 180
    let lon1 = self.longitude * Double.pi / 180
    
    let lat2 = asin(sin(lat1) * cos(distRadians) + cos(lat1) * sin(distRadians) * cos(bearingRadians))
    let lon2 = lon1 + atan2(sin(bearingRadians) * sin(distRadians) * cos(lat1), cos(distRadians) - sin(lat1) * sin(lat2))
    
    return CLLocationCoordinate2D(latitude: lat2 * 180 / Double.pi, longitude: lon2 * 180 / Double.pi)
  }
}

extension MKCoordinateRegion: Equatable {
  public static func == (lhs: MKCoordinateRegion, rhs: MKCoordinateRegion) -> Bool {
    return lhs.center == rhs.center && lhs.span == rhs.span
  }
}

extension CLLocationCoordinate2D: Comparable {
  public static func < (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
    return lhs.latitude < rhs.latitude && lhs.longitude < rhs.longitude
  }
}

extension MKCoordinateSpan: Equatable {
  public static func == (lhs: MKCoordinateSpan, rhs: MKCoordinateSpan) -> Bool {
    return lhs.latitudeDelta == rhs.latitudeDelta && lhs.longitudeDelta == rhs.longitudeDelta
  }
}

extension MKCoordinateRegion {
  public var sizeInMeters: SizeInMeters {
    let westCenter = CLLocation(latitude: center.latitude - span.latitudeDelta * 0.5, longitude: center.longitude)
    let eastCenter = CLLocation(latitude: center.latitude + span.latitudeDelta * 0.5, longitude: center.longitude)
    
    let northCenter = CLLocation(latitude: center.latitude, longitude: center.longitude - span.longitudeDelta * 0.5)
    let southCenter = CLLocation(latitude: center.latitude, longitude: center.longitude + span.longitudeDelta * 0.5)
    
    let width = westCenter.distance(from: eastCenter)
    let height = northCenter.distance(from: southCenter)
    
    return SizeInMeters(width: width, height: height)
  }
}

extension MKMapView {
  var corners: MapCorners {
    let topLeft = CGPoint(x: bounds.origin.x, y: bounds.origin.y)
    let topRight = CGPoint(x: bounds.origin.x, y: bounds.origin.y + bounds.size.height)
    let bottomLeft = CGPoint(x: bounds.origin.x + bounds.size.width, y: bounds.origin.y)
    let bottomRight = CGPoint(x: bounds.origin.x + bounds.size.width, y: bounds.origin.y + bounds.size.height)
    
    let topLeftCoord = convert(topLeft, toCoordinateFrom: self)
    let topRightCoord = convert(topRight, toCoordinateFrom: self)
    let bottomLeftCoord = convert(bottomLeft, toCoordinateFrom: self)
    let bottomRightCoord = convert(bottomRight, toCoordinateFrom: self)
    
    return MapCorners(
      topLeft: CLLocationCoordinate2D(latitude: topLeftCoord.latitude, longitude: topLeftCoord.longitude),
      topRight: CLLocationCoordinate2D(latitude: topRightCoord.latitude, longitude: topRightCoord.longitude),
      bottomLeft: CLLocationCoordinate2D(latitude: bottomLeftCoord.latitude, longitude: bottomLeftCoord.longitude),
      bottomRight: CLLocationCoordinate2D(latitude: bottomRightCoord.latitude, longitude: bottomRightCoord.longitude)
    )
  }
}

public struct MapCorners {
  let topLeft: CLLocationCoordinate2D
  let topRight: CLLocationCoordinate2D
  let bottomLeft: CLLocationCoordinate2D
  let bottomRight: CLLocationCoordinate2D
}

/// Use this to capture size of a region in meters
public struct SizeInMeters {
  public let width: CLLocationDistance
  public let height: CLLocationDistance
  
  public init(width: CLLocationDistance, height: CLLocationDistance) {
    self.width = width
    self.height = height
  }
}
