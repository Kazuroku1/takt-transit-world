import Foundation

public enum VehicleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case bus, tram, train, intercity, metro, ship, cable, plane
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bus: return "Bus"
        case .tram: return "Tram"
        case .train: return "S-Bahn"
        case .intercity: return "Fernzug"
        case .metro: return "Metro"
        case .ship: return "Schiff"
        case .cable: return "Seilbahn"
        case .plane: return "Flugzeug"
        }
    }
    public var symbol: String {
        switch self {
        case .bus: return "bus.fill"
        case .tram: return "tram.fill"
        case .train, .intercity: return "train.side.front.car"
        case .metro: return "tram.tunnel.fill"
        case .ship: return "ferry.fill"
        case .cable: return "cablecar.fill"
        case .plane: return "airplane"
        }
    }
    public var level: Int { switch self { case .bus: return 1; case .tram: return 2; case .train: return 3; case .intercity: return 5; case .plane: return 7; case .metro, .ship, .cable: return 99 } }
    public var colorHex: UInt32 {
        switch self {
        case .bus: return 0xDFA137
        case .tram: return 0xDF725C
        case .train: return 0x628CB0
        case .intercity: return 0xBB4652
        case .metro: return 0x9A81B5
        case .ship: return 0x55A69E
        case .cable: return 0x859E54
        case .plane: return 0xD48DA9
        }
    }
    public var motto: String {
        switch self {
        case .bus: return "Kleine Wege. Grosse Verbindungen."
        case .tram: return "Der Herzschlag deiner Innenstadt."
        case .train: return "Vom Umland ins Zentrum."
        case .intercity: return "Die Schweiz wächst zusammen."
        case .metro: return "Unter der Stadt geht es vorwärts."
        case .ship: return "Dein Netz geht übers Wasser."
        case .cable: return "Mit Aussicht nach ganz oben."
        case .plane: return "Schweizer Flughäfen verbinden."
        }
    }
}

public struct MapPoint: Codable, Equatable, Sendable {
    public let x: Double
    public let z: Double
    public init(_ x: Double, _ z: Double) { self.x = x; self.z = z }
}

public struct TransitRoute: Identifiable, Sendable {
    public let id: String
    public let number: String
    public let name: String
    public let kind: VehicleKind
    public let price: Int
    public let duration: Double
    public let capacity: Int
    public let fare: Int
    public let colorHex: UInt32
    public let stops: [String]
    public let points: [MapPoint]
    public var requiredLevel: Int { kind.level }
    public func upgradePrice(tier: Int) -> Int {
        Int((Double(max(400, price)) * (0.55 + Double(tier) * 0.45)).rounded())
    }
    public func incomePerMinute(tier: Int) -> Int {
        Int((Double(capacity * tier * fare) * 60 / duration).rounded())
    }
    public func stopNames(in cityID: String) -> [String] {
        if cityID == "zurich", kind != .plane, let names = ZurichRouteGeometry.stops[id] { return names }
        return SwissGeography.stopNames(routeID: id, cityID: cityID) ?? stops
    }
    public func points(in cityID: String) -> [MapPoint] {
        if cityID == "zurich", let path = ZurichRouteGeometry.paths[id], kind != .plane { return path }
        return SwissGeography.points(routeID: id, cityID: cityID) ?? points.map { MapPoint($0.x + Catalog.city(cityID).mapCenter.x, $0.z + Catalog.city(cityID).mapCenter.z) }
    }
    public func spatialNote(in cityID: String) -> String {
        guard cityID == "zurich" else { return "Geografisch eingeordnete Spielverbindung. Strecken und Fahrpläne sind vereinfacht, kein reales Verkehrsangebot." }
        switch kind {
        case .bus, .tram: return "Amtlicher Linienverlauf, für das Spiel vereinfacht. Die Fahrzeuge pendeln auf einer Fahrtrichtung; gezeigt sind die Endhaltestellen."
        case .train: return "Amtlicher S12-Verlauf im Kartenausschnitt, vereinfacht. Ausgewählte Haltestellen; Tunnel werden sichtbar dargestellt."
        case .intercity: return "Vereinfachte Fernverbindung zwischen Schweizer Regionen; keine exakte Fahrplanauskunft."
        case .ship: return "Spielerisch angenäherte Seestrecke zwischen realen Anlegestellen."
        case .metro: return "Fiktive Erweiterung: Zürich hat keine Metro. Diese Strecke gehört zu deinem Spielnetz."
        case .cable: return "Fiktive Seilbahn für dein Spielnetz; kein reales Verkehrsangebot."
        case .plane: return "Spielerische Verbindung zwischen realen Schweizer Flughäfen; kein realer Flugplan."
        }
    }
}

public struct TransitCity: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let country: String
    public let flag: String
    public let motto: String
    public let price: Int
    public let requiredLevel: Int
    public let x: Double
    public let y: Double
    public let tint: UInt32
    public var mapCenter: MapPoint { SwissGeography.center(for: id) }
    public var predecessorID: String? {
        guard let index = Catalog.cities.firstIndex(where: { $0.id == id }), index > 0 else { return nil }
        return Catalog.cities[index - 1].id
    }
    public var allowedKinds: [VehicleKind] {
        var kinds: [VehicleKind] = [.bus]
        if ["zurich", "bern", "basel", "geneva"].contains(id) { kinds.append(.tram) }
        if ["luzern", "zurich", "bern", "basel", "geneva"].contains(id) { kinds += [.train, .intercity] }
        if ["zurich", "basel", "geneva"].contains(id) { kinds.append(.plane) }
        return kinds
    }
}

public enum Catalog {
    public static let playableKinds: [VehicleKind] = [.bus, .tram, .train, .intercity, .plane]
    public static let cities: [TransitCity] = [
        .init(id: "andermatt", name: "Andermatt", country: "Schweiz", flag: "🇨🇭", motto: "Dein erster Bergbus.", price: 0, requiredLevel: 1, x: 0.62, y: 0.58, tint: 0x75A98A),
        .init(id: "altdorf", name: "Altdorf", country: "Schweiz", flag: "🇨🇭", motto: "Vom Berg hinunter ins Tal.", price: 2800, requiredLevel: 2, x: 0.61, y: 0.46, tint: 0x75A98A),
        .init(id: "schwyz", name: "Schwyz", country: "Schweiz", flag: "🇨🇭", motto: "Die kleinen Orte verbinden.", price: 5000, requiredLevel: 3, x: 0.59, y: 0.39, tint: 0x75A98A),
        .init(id: "luzern", name: "Luzern", country: "Schweiz", flag: "🇨🇭", motto: "Am See beginnt dein Bahnnetz.", price: 18000, requiredLevel: 4, x: 0.51, y: 0.4, tint: 0x75A98A),
        .init(id: "zurich", name: "Zürich", country: "Schweiz", flag: "🇨🇭", motto: "Bus, Tram und die grosse Stadt.", price: 65000, requiredLevel: 5, x: 0.62, y: 0.23, tint: 0x75A98A),
        .init(id: "bern", name: "Bern", country: "Schweiz", flag: "🇨🇭", motto: "Dein Netz erreicht die Bundesstadt.", price: 350000, requiredLevel: 6, x: 0.32, y: 0.44, tint: 0x75A98A),
        .init(id: "basel", name: "Basel", country: "Schweiz", flag: "🇨🇭", motto: "Verbindungen am Rhein.", price: 900000, requiredLevel: 7, x: 0.35, y: 0.12, tint: 0x75A98A),
        .init(id: "geneva", name: "Genève", country: "Schweiz", flag: "🇨🇭", motto: "Vom Gotthard bis an den Léman.", price: 2500000, requiredLevel: 8, x: 0.07, y: 0.79, tint: 0x75A98A)
    ]

    public static let routes: [TransitRoute] = [
        .init(id: "b31", number: "31", name: "Die Quartierlinie", kind: .bus, price: 0, duration: 14, capacity: 8, fare: 4, colorHex: 0xDFA137,
              stops: ["Altstetten", "Hardplatz", "Langstrasse", "Hauptbahnhof"], points: [.init(-10,9),.init(-10,3),.init(-10,-3),.init(-4,-3),.init(-4,-9),.init(2,-9)]),
        .init(id: "b33", number: "33", name: "Einmal ums Quartier", kind: .bus, price: 550, duration: 18, capacity: 12, fare: 4, colorHex: 0x7E9F63,
              stops: ["Triemli", "Wiedikon", "Central", "Bellevue", "Tiefenbrunnen"], points: [.init(-4,9),.init(-4,3),.init(-4,-3),.init(2,-3),.init(2,3),.init(12,3),.init(12,9)]),
        .init(id: "t4", number: "4", name: "Mitten durchs Leben", kind: .tram, price: 1100, duration: 20, capacity: 24, fare: 5, colorHex: 0xDF725C,
              stops: ["Bahnhofquai", "Hauptbahnhof", "Central", "Bellevue"], points: [.init(-10,-9),.init(-4,-9),.init(2,-9),.init(2,-3),.init(2,3),.init(12,3),.init(12,9)]),
        .init(id: "t8", number: "8", name: "Die kleine Stadtrunde", kind: .tram, price: 1800, duration: 22, capacity: 28, fare: 5, colorHex: 0xAF7B9E,
              stops: ["Hardplatz", "Stauffacher", "Kunsthaus", "Opernhaus"], points: [.init(-10,3),.init(-4,3),.init(-4,-3),.init(2,-3),.init(12,-3),.init(12,3)]),
        .init(id: "s12", number: "S12", name: "Über die Stadt hinaus", kind: .train, price: 2600, duration: 24, capacity: 52, fare: 6, colorHex: 0x628CB0,
              stops: ["Altstetten", "Hauptbahnhof", "Stadelhofen"], points: [.init(-14,-11.8),.init(-4,-11.8),.init(2,-11.8),.init(14,-11.8)]),
        .init(id: "ic1", number: "IC", name: "Die Schweiz verbindet", kind: .intercity, price: 6200, duration: 32, capacity: 110, fare: 9, colorHex: 0xBB4652,
              stops: ["Hauptbahnhof", "Nachbarregion"], points: [.init(-14,-12),.init(14,-12)]),
        .init(id: "m1", number: "M1", name: "Unterwegs im Untergrund", kind: .metro, price: 3800, duration: 18, capacity: 64, fare: 6, colorHex: 0x9A81B5,
              stops: ["Universität", "Central", "Paradeplatz", "Seefeld"], points: [.init(-10,-9),.init(-10,-3),.init(-4,-3),.init(-4,3),.init(2,3),.init(2,9)]),
        .init(id: "l1", number: "L1", name: "Eine kleine Seereise", kind: .ship, price: 5200, duration: 28, capacity: 75, fare: 8, colorHex: 0x55A69E,
              stops: ["Landesmuseum", "Bürkliplatz", "Zürichhorn"], points: [.init(7.8,-12),.init(7.8,-3),.init(7.8,3),.init(7.8,12)]),
        .init(id: "c1", number: "C1", name: "Hoch hinaus", kind: .cable, price: 7200, duration: 16, capacity: 28, fare: 10, colorHex: 0x859E54,
              stops: ["Talstation", "Uetliberg"], points: [.init(-7,-7),.init(-11,-11),.init(-15,-15)]),
        .init(id: "a1", number: "LX", name: "Hallo, Welt!", kind: .plane, price: 10000, duration: 35, capacity: 160, fare: 12, colorHex: 0xD48DA9,
              stops: ["Flughafen", "International"], points: [.init(-14,12),.init(-8,3),.init(0,-5),.init(9,-14),.init(16,-20)])
    ]
    public static func routes(in cityID: String) -> [TransitRoute] {
        guard let city = cities.first(where: { $0.id == cityID }) else { return [] }
        return routes.filter { city.allowedKinds.contains($0.kind) }
    }
    public static func route(_ id: String) -> TransitRoute? { routes.first { $0.id == id } }
    public static func city(_ id: String) -> TransitCity { cities.first { $0.id == id } ?? cities[0] }
}
