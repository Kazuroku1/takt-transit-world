import Foundation

/// Offline, triangulated municipal map. One world unit is 100 metres.
/// x is LV95 easting, z is negative LV95 northing, relative to `center`.
public struct CityMap: Codable, Sendable {
    public let version: Int
    public let cityID: String
    public let center: [Double]
    public let metersPerUnit: Double
    public let bounds: [Float]
    public let attribution: String
    public let heightNote: String
    public let sourceDate: String
    public let sourceCounts: [String: Int]
    public let statistics: [String: Int]
    public let boundary: [[[Float]]]
    public let labels: [CityMapLabel]
    public let tiles: [CityMapTile]

    public static func load(from url: URL) throws -> CityMap {
        try JSONDecoder().decode(CityMap.self, from: Data(contentsOf: url, options: .mappedIfSafe))
    }
}

public struct CityMapLabel: Codable, Sendable {
    public let name: String
    public let x: Float
    public let z: Float
}

public struct CityMapTile: Codable, Sendable {
    public let id: String
    /// minX, minZ, maxX, maxZ; includes buildings crossing tile edges.
    public let bounds: [Float]
    public let meshes: [CityMapMesh]
}

public struct CityMapMesh: Codable, Sendable {
    /// water, park, forest, road, building, building2, building3, roof.
    public let kind: String
    /// Flat xyz array, with up-facing roofs and land-cover triangles.
    public let positions: [Float]
    public let indices: [UInt32]
}
