import Foundation

public enum VehicleKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case bus, tram, train, metro, ship, cable, plane
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .bus: return "Bus"
        case .tram: return "Tram"
        case .train: return "Zug"
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
        case .train: return "train.side.front.car"
        case .metro: return "tram.tunnel.fill"
        case .ship: return "ferry.fill"
        case .cable: return "cablecar.fill"
        case .plane: return "airplane"
        }
    }
    public var level: Int { Self.allCases.firstIndex(of: self)! + 1 }
    public var colorHex: UInt32 {
        switch self {
        case .bus: return 0xDFA137
        case .tram: return 0xDF725C
        case .train: return 0x628CB0
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
        case .train: return "Mehr Menschen. Neue Horizonte."
        case .metro: return "Unter der Stadt geht es vorwärts."
        case .ship: return "Dein Netz geht übers Wasser."
        case .cable: return "Mit Aussicht nach ganz oben."
        case .plane: return "Die Welt liegt dir zu Füssen."
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
        guard let names = Catalog.terminals[cityID], let index = Catalog.routes.firstIndex(where: { $0.id == id }) else { return stops }
        return stops.indices.map { names[(index + $0) % names.count] }
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
}

public enum Catalog {
    public static let cities: [TransitCity] = [
        .init(id: "zurich", name: "Zürich", country: "Schweiz", flag: "🇨🇭", motto: "Zwischen See und Stadtleben.", price: 0, requiredLevel: 1, x: 0.49, y: 0.31, tint: 0x75A98A),
        .init(id: "bern", name: "Bern", country: "Schweiz", flag: "🇨🇭", motto: "Eine Altstadt voller neuer Wege.", price: 2800, requiredLevel: 3, x: 0.47, y: 0.33, tint: 0xC49D71),
        .init(id: "paris", name: "Paris", country: "Frankreich", flag: "🇫🇷", motto: "Nächster Halt: la vie en rose.", price: 6500, requiredLevel: 4, x: 0.45, y: 0.29, tint: 0xB09AAB),
        .init(id: "london", name: "London", country: "Grossbritannien", flag: "🇬🇧", motto: "Ein neuer Takt an der Themse.", price: 12000, requiredLevel: 5, x: 0.43, y: 0.24, tint: 0xA4A8BC),
        .init(id: "newyork", name: "New York", country: "USA", flag: "🇺🇸", motto: "Ein Netz, das niemals schläft.", price: 20000, requiredLevel: 6, x: 0.25, y: 0.34, tint: 0xB7A183),
        .init(id: "tokyo", name: "Tokio", country: "Japan", flag: "🇯🇵", motto: "Millionen Menschen. Dein Takt.", price: 35000, requiredLevel: 7, x: 0.87, y: 0.39, tint: 0xD4A2AE),
        .init(id: "rio", name: "Rio de Janeiro", country: "Brasilien", flag: "🇧🇷", motto: "Verbindungen mit Meeresbrise.", price: 45000, requiredLevel: 8, x: 0.34, y: 0.71, tint: 0x88AF77),
        .init(id: "sydney", name: "Sydney", country: "Australien", flag: "🇦🇺", motto: "Die Welt ist erst der Anfang.", price: 60000, requiredLevel: 9, x: 0.91, y: 0.78, tint: 0xD0B178)
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
        .init(id: "m1", number: "M1", name: "Unterwegs im Untergrund", kind: .metro, price: 3800, duration: 18, capacity: 64, fare: 6, colorHex: 0x9A81B5,
              stops: ["Universität", "Central", "Paradeplatz", "Seefeld"], points: [.init(-10,-9),.init(-10,-3),.init(-4,-3),.init(-4,3),.init(2,3),.init(2,9)]),
        .init(id: "l1", number: "L1", name: "Eine kleine Seereise", kind: .ship, price: 5200, duration: 28, capacity: 75, fare: 8, colorHex: 0x55A69E,
              stops: ["Landesmuseum", "Bürkliplatz", "Zürichhorn"], points: [.init(7.8,-12),.init(7.8,-3),.init(7.8,3),.init(7.8,12)]),
        .init(id: "c1", number: "C1", name: "Hoch hinaus", kind: .cable, price: 7200, duration: 16, capacity: 28, fare: 10, colorHex: 0x859E54,
              stops: ["Talstation", "Uetliberg"], points: [.init(-7,-7),.init(-11,-11),.init(-15,-15)]),
        .init(id: "a1", number: "LX", name: "Hallo, Welt!", kind: .plane, price: 10000, duration: 35, capacity: 160, fare: 12, colorHex: 0xD48DA9,
              stops: ["Flughafen", "International"], points: [.init(-14,12),.init(-8,3),.init(0,-5),.init(9,-14),.init(16,-20)])
    ]
    public static func route(_ id: String) -> TransitRoute? { routes.first { $0.id == id } }
    public static func city(_ id: String) -> TransitCity { cities.first { $0.id == id } ?? cities[0] }
    static let terminals: [String: [String]] = [
        "bern": ["Bümpliz","Bahnhof Bern","Wabern","Zytglogge","Wankdorf","Paul Klee"],
        "paris": ["Montmartre","Gare du Nord","Bastille","Tour Eiffel","Châtelet","Opéra"],
        "london": ["Camden","King’s Cross","Brixton","Greenwich","Waterloo","Westminster"],
        "newyork": ["Harlem","Grand Central","Brooklyn","Queens","Times Square","Downtown"],
        "tokyo": ["Shinjuku","Tokyo Station","Shibuya","Asakusa","Ginza","Ueno"],
        "rio": ["Centro","Central do Brasil","Copacabana","Ipanema","Lapa","Botafogo"],
        "sydney": ["Newtown","Central","Bondi","Circular Quay","Town Hall","Manly"]
    ]
}
