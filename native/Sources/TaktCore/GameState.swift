import Foundation

public struct OwnedLine: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var tier = 1
    public var carried = 0
    public var progress = 0.0
    public init(id: String) { self.id = id }
}
public struct CityNetwork: Codable, Equatable, Sendable {
    public var lines: [OwnedLine]
    public init(lines: [OwnedLine] = [OwnedLine(id: "b31")]) { self.lines = lines }
}
public struct GameSettings: Codable, Equatable, Sendable {
    public var night = false
    public var sound = false
    public var haptics = true
    public var reducedMotion = false
    public init() {}
}
public struct TransitEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case rush, festival }
    public var kind: Kind
    public var endsAt: Double
    public var title: String { kind == .rush ? "Feierabendverkehr!" : "Stadtfest!" }
}
public struct GameState: Codable, Equatable, Sendable {
    public var version = 3
    public var coins = 1200
    public var xp = 0
    public var passengers = 0
    public var earned = 0
    public var cityID = "andermatt"
    public var networks: [String: CityNetwork] = ["andermatt": CityNetwork()]
    public var claimed: Set<String> = []
    public var seconds = 0.0
    public var lastEvent = 0.0
    public var event: TransitEvent?
    public var settings = GameSettings()
    public var dailyDate = ""
    public var dailyEarned = 0
    public init() {}
    public var level: Int { Int(sqrt(Double(xp) / 90)) + 1 }
    public static func xpNeeded(for level: Int) -> Int { max(0, level - 1) * max(0, level - 1) * 90 }
    public var levelProgress: Double {
        Double(xp - Self.xpNeeded(for: level)) / Double(Self.xpNeeded(for: level + 1) - Self.xpNeeded(for: level))
    }
    public var currentCity: TransitCity { Catalog.city(cityID) }
    public var currentLines: [OwnedLine] { networks[cityID]?.lines ?? [] }
    public var allLines: [OwnedLine] { networks.values.flatMap(\.lines) }
    public var income: Int { allLines.reduce(0) { $0 + (Catalog.route($1.id)?.incomePerMinute(tier: $1.tier) ?? 0) } }
    public func owned(_ id: String) -> OwnedLine? { currentLines.first { $0.id == id } }
    public func ownsKind(_ kind: VehicleKind) -> Bool { allLines.contains { Catalog.route($0.id)?.kind == kind } }

    public func regionUnlockReason(cityID: String) -> String? {
        guard let city = Catalog.cities.first(where: { $0.id == cityID }) else { return "Diese Region gibt es nicht." }
        if networks[cityID] != nil { return nil }
        if let previous = city.predecessorID, networks[previous] == nil { return "Erschliesse zuerst \(Catalog.city(previous).name)." }
        if level < city.requiredLevel { return "Ab Level \(city.requiredLevel)." }
        return nil
    }
    public var isValid: Bool {
        guard version == 3, coins >= 0, xp >= 0, xp < 1_000_000_000,
              passengers >= 0, earned >= 0, dailyEarned >= 0, dailyEarned < 1_000_000_000_000,
              coins < 1_000_000_000_000, passengers < 1_000_000_000_000, earned < 1_000_000_000_000,
              seconds.isFinite, seconds >= 0, seconds < 1_000_000_000_000, lastEvent.isFinite, lastEvent >= 0, lastEvent < 1_000_000_000_000,
              networks[cityID] != nil, networks["andermatt"] != nil else { return false }
        for (id, network) in networks {
            if let previous = Catalog.city(id).predecessorID, networks[previous] == nil { return false }
            guard Catalog.cities.contains(where: { $0.id == id }), !network.lines.isEmpty,
                  Set(network.lines.map(\.id)).count == network.lines.count else { return false }
            for line in network.lines {
                guard let route = Catalog.routes(in: id).first(where: { $0.id == line.id }), (1...5).contains(line.tier),
                      line.carried >= 0, line.carried < 1_000_000_000_000, line.progress.isFinite, line.progress >= 0,
                      line.progress < route.duration else { return false }
            }
        }
        return event == nil || (event!.endsAt.isFinite && event!.endsAt >= 0 && event!.endsAt < 1_000_000_000_000)
    }
}

public struct Quest: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let progress: Int
    public let target: Int
    public let reward: Int
    public let xp: Int
    public var ready: Bool { progress >= target }
    public var fraction: Double { min(1, Double(progress) / Double(target)) }
}

public enum GameAction: Sendable {
    case buy(String), upgrade(String), claim(String), visit(String)
}
public enum GameRuleError: Error, Equatable, LocalizedError {
    case unknown, alreadyOwned, locked(Int), prerequisite(String), insufficientFunds(Int), maxTier, unfinished, alreadyClaimed
    public var errorDescription: String? {
        switch self {
        case .prerequisite(let reason): return reason
        case .unknown: return "Diese Verbindung gibt es noch nicht."
        case .alreadyOwned: return "Diese Linie ist bereits in Betrieb."
        case .locked(let level): return "Erreichbar ab Level \(level)."
        case .insufficientFunds(let missing): return "Es fehlen noch \(missing) Münzen."
        case .maxTier: return "Diese Linie ist vollständig ausgebaut."
        case .unfinished: return "Diese Aufgabe ist noch in Arbeit."
        case .alreadyClaimed: return "Diese Belohnung hast du schon abgeholt."
        }
    }
}

public enum GameRules {
    public static func localDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 2026, c.month ?? 1, c.day ?? 1)
    }
    public static func quests(_ s: GameState, day: String) -> [Quest] {
        let lines = s.allLines
        var result: [Quest] = [
            .init(id: "second", title: "Zwei Busse am Berg", detail: "Eröffne die zweite Buslinie in Andermatt.", progress: s.networks["andermatt"]?.lines.contains(where: { $0.id == "b33" }) == true ? 1 : 0, target: 1, reward: 650, xp: 100),
            .init(id: "first50", title: "Die ersten 50", detail: "Bringe 50 Menschen an ihr Ziel.", progress: min(50,s.passengers), target: 50, reward: 400, xp: 100),
            .init(id: "upgrade", title: "Mehr Platz im Bergbus", detail: "Baue eine Linie auf zwei Fahrzeuge aus.", progress: lines.contains { $0.tier > 1 } ? 1 : 0, target: 1, reward: 650, xp: 100),
            .init(id: "p500", title: "Das Tal bewegt sich", detail: "Befördere insgesamt 500 Fahrgäste.", progress: min(500,s.passengers), target: 500, reward: 1800, xp: 300),
            .init(id: "tram", title: "Die Stadt auf Schienen", detail: "Beginne mit dem Stadtbus, dann eröffne eine Tramlinie in einer Tramstadt.", progress: s.ownsKind(.tram) ? 1 : 0, target: 1, reward: 1800, xp: 300),
            .init(id: "rail", title: "Vom Umland ins Zentrum", detail: "Eröffne nach dem lokalen Netz deine erste S-Bahn.", progress: s.ownsKind(.train) ? 1 : 0, target: 1, reward: 2600, xp: 400),
            .init(id: "intercity", title: "Die Regionen wachsen zusammen", detail: "Erweitere eine S-Bahn-Region um einen Fernzug.", progress: s.ownsKind(.intercity) ? 1 : 0, target: 1, reward: 5000, xp: 700),
            .init(id: "plane", title: "Über den Wolken", detail: "Verbinde nach dem Fernverkehr einen Schweizer Flughafen.", progress: s.ownsKind(.plane) ? 1 : 0, target: 1, reward: 9000, xp: 1000)
        ]
        for (index, city) in Catalog.cities.dropFirst().enumerated() {
            result.append(.init(id: "region-" + city.id, title: "Nächster Halt: " + city.name,
                detail: "Erschliesse \(city.name) nach \(Catalog.city(city.predecessorID!).name). Dein erster Bus wartet.",
                progress: s.networks[city.id] == nil ? 0 : 1, target: 1, reward: min(5000, city.price / 5), xp: 200 + index * 150))
        }
        result.append(.init(id: "p5000", title: "Tausend kleine Geschichten", detail: "Befördere 5 000 Fahrgäste.", progress: min(5000,s.passengers), target: 5000, reward: 7500, xp: 1200))
        result.append(.init(id: "switzerland8", title: "Die Schweiz im Takt", detail: "Verbinde alle acht Regionen vom Gotthard bis nach Genève.", progress: s.networks.count, target: 8, reward: 25000, xp: 3000))
        result.append(.init(id: "daily-" + day, title: "Heute läuft’s rund", detail: "Verdiene heute 5 000 Münzen mit deinen Linien.", progress: s.dailyDate == day ? min(5000,s.dailyEarned) : 0, target: 5000, reward: 1500, xp: 200))
        return result
    }

    /// Region and local transport progression, excluding the separately displayed price.
    public static func unlockReason(route: TransitRoute, state: GameState) -> String? {
        guard Catalog.routes(in: state.cityID).contains(where: { $0.id == route.id }), state.networks[state.cityID] != nil else {
            return "Dieses Verkehrsmittel gehört nicht zu dieser Region."
        }
        if state.level < route.requiredLevel { return "Ab Level \(route.requiredLevel)." }
        let local = state.currentLines.compactMap { Catalog.route($0.id)?.kind }
        switch route.kind {
        case .bus: return nil
        case .tram: return local.contains(.bus) ? nil : "Beginne mit einem Bus in dieser Stadt."
        case .train:
            guard state.ownsKind(.tram) else { return "Eröffne zuerst eine Tramlinie in Zürich. Danach wird die S-Bahn-Technik verfügbar." }
            if state.currentCity.allowedKinds.contains(.tram) { return local.contains(.tram) ? nil : "Eröffne zuerst eine Tramlinie in dieser Stadt." }
            return state.owned("b33") != nil ? nil : "Baue zuerst das lokale Busnetz mit einer zweiten Linie aus."
        case .intercity: return local.contains(.train) ? nil : "Eröffne zuerst eine S-Bahn in dieser Region."
        case .plane: return local.contains(.intercity) ? nil : "Verbinde zuerst die Region mit einem Fernzug."
        case .metro, .ship, .cable: return "Dieses Verkehrsmittel gehört nicht zum Schweizer Ausbaupfad."
        }
    }

    /// All checks precede mutations: rejected actions leave the complete state unchanged.
    public static func apply(_ action: GameAction, to s: inout GameState, day: String) throws {
        switch action {
        case .buy(let id):
            guard let route = Catalog.route(id) else { throw GameRuleError.unknown }
            guard s.owned(id) == nil else { throw GameRuleError.alreadyOwned }
            if let reason = unlockReason(route: route, state: s) { throw GameRuleError.prerequisite(reason) }
            guard s.coins >= route.price else { throw GameRuleError.insufficientFunds(route.price - s.coins) }
            s.networks[s.cityID]!.lines.append(OwnedLine(id: id))
            s.coins -= route.price; s.xp += 50
        case .upgrade(let id):
            guard let route = Catalog.routes(in: s.cityID).first(where: { $0.id == id }), let index = s.currentLines.firstIndex(where: { $0.id == id }) else { throw GameRuleError.unknown }
            let line = s.currentLines[index]
            guard line.tier < 5 else { throw GameRuleError.maxTier }
            let cost = route.upgradePrice(tier: line.tier)
            guard s.coins >= cost else { throw GameRuleError.insufficientFunds(cost - s.coins) }
            s.networks[s.cityID]!.lines[index].tier += 1
            s.coins -= cost; s.xp += 70
        case .claim(let id):
            guard let quest = quests(s, day: day).first(where: { $0.id == id }) else { throw GameRuleError.unknown }
            guard !s.claimed.contains(id) else { throw GameRuleError.alreadyClaimed }
            guard quest.ready else { throw GameRuleError.unfinished }
            s.claimed.insert(id); s.coins += quest.reward; s.xp += quest.xp
        case .visit(let id):
            guard let city = Catalog.cities.first(where: { $0.id == id }) else { throw GameRuleError.unknown }
            if s.networks[id] == nil {
                if let reason = s.regionUnlockReason(cityID: id) { throw GameRuleError.prerequisite(reason) }
                guard s.coins >= city.price else { throw GameRuleError.insufficientFunds(city.price - s.coins) }
                s.coins -= city.price; s.xp += 150; s.networks[id] = CityNetwork()
            }
            s.cityID = id
        }
    }

    /// Simulation-only time; callers suspend this on backgrounding. Integer-second
    /// substeps keep trip rewards stable at event boundaries and across frame rates.
    public static func advance(_ s: inout GameState, by delta: Double, day: String) {
        guard delta.isFinite, delta > 0 else { return }
        var remaining = min(delta, 5)
        if s.dailyDate != day { s.dailyDate = day; s.dailyEarned = 0 }
        while remaining > 0.000001 {
            let boundary = floor(s.seconds + 0.0000001) + 1
            let step = min(remaining, max(0.000001, boundary - s.seconds))
            s.seconds += step; remaining -= step
            if let event = s.event, s.seconds >= event.endsAt { s.event = nil }
            if s.event == nil, s.seconds - s.lastEvent >= 120 {
                s.event = TransitEvent(kind: Int(s.seconds / 120) % 2 == 0 ? .festival : .rush, endsAt: s.seconds + 35)
                s.lastEvent = s.seconds
            }
            var carried = 0, income = 0
            for cityID in s.networks.keys.sorted() {
                var network = s.networks[cityID]!
                for index in network.lines.indices {
                    guard let route = Catalog.route(network.lines[index].id) else { continue }
                    network.lines[index].progress += step
                    let trips = Int(floor((network.lines[index].progress + 0.0000001) / route.duration))
                    let count = trips * route.capacity * network.lines[index].tier
                    network.lines[index].progress = max(0, network.lines[index].progress - Double(trips) * route.duration)
                    network.lines[index].carried += count
                    carried += count
                    income += s.event == nil ? count * route.fare : count * route.fare * 3 / 2
                }
                s.networks[cityID] = network
            }
            s.xp += (s.passengers + carried) / 3 - s.passengers / 3
            s.passengers += carried; s.coins += income; s.earned += income; s.dailyEarned += income
        }
    }
}

public enum SaveCodec {
    public static func encode(_ state: GameState) throws -> Data { try JSONEncoder().encode(state) }
    public static func decode(_ data: Data) throws -> GameState {
        var state = try JSONDecoder().decode(GameState.self, from: data)
        if state.version == 2 { state = try migrateV2(state) }
        guard state.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return state
    }
    /// Keep Swiss assets and all earned statistics. Retired world assets are refunded
    /// at their original purchase/upgrade prices; predecessor bus regions are granted.
    private static func migrateV2(_ old: GameState) throws -> GameState {
        let oldPrices = ["zurich": 0, "bern": 2800, "paris": 6500, "london": 12000,
                         "newyork": 20000, "tokyo": 35000, "rio": 45000, "sydney": 60000]
        guard old.coins >= 0, old.coins < 1_000_000_000_000, old.xp >= 0, old.xp < 1_000_000_000,
              old.networks[old.cityID] != nil, old.networks["zurich"] != nil else { throw CocoaError(.fileReadCorruptFile) }
        var result = old
        result.version = 3
        result.networks = [:]
        for (cityID, network) in old.networks {
            guard let cityPrice = oldPrices[cityID], !network.lines.isEmpty,
                  Set(network.lines.map(\.id)).count == network.lines.count else { throw CocoaError(.fileReadCorruptFile) }
            let retainedCity = cityID == "zurich" || cityID == "bern"
            var kept: [OwnedLine] = []
            if !retainedCity { result.coins += cityPrice }
            for line in network.lines {
                guard let route = Catalog.route(line.id), route.kind != .intercity,
                      (1...5).contains(line.tier), line.carried >= 0, line.carried < 1_000_000_000_000, line.progress.isFinite,
                      line.progress >= 0, line.progress < route.duration else { throw CocoaError(.fileReadCorruptFile) }
                if retainedCity && Catalog.routes(in: cityID).contains(where: { $0.id == line.id }) {
                    kept.append(line)
                } else {
                    result.coins += route.price
                    for tier in 1..<line.tier { result.coins += route.upgradePrice(tier: tier) }
                }
            }
            if retainedCity { result.networks[cityID] = CityNetwork(lines: kept.isEmpty ? [OwnedLine(id: "b31")] : kept) }
        }
        let furthest = result.networks["bern"] != nil ? 5 : 4
        for city in Catalog.cities.prefix(furthest + 1) where result.networks[city.id] == nil { result.networks[city.id] = CityNetwork() }
        result.cityID = result.networks[old.cityID] != nil ? old.cityID : "andermatt"
        guard result.isValid else { throw CocoaError(.fileReadCorruptFile) }
        return result
    }

}

public struct RoutePose: Sendable {
    public let x: Double
    public let z: Double
    public let heading: Double
    public let fraction: Double
}
public enum RouteMotion {
    /// One trip is one direction. A brief dwell at both terminals makes arrivals legible.
    public static func pose(points: [MapPoint], phase: Double) -> RoutePose {
        guard points.count > 1, phase.isFinite else { return .init(x: points.first?.x ?? 0, z: points.first?.z ?? 0, heading: 0, fraction: 0) }
        let cycle = phase - floor(phase / 2) * 2
        let outbound = cycle < 1
        let trip = outbound ? cycle : cycle - 1
        let movement = min(1, max(0, (trip - 0.04) / 0.92))
        let fraction = outbound ? movement : 1 - movement
        let lengths = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.z - $0.z) }
        let total = lengths.reduce(0,+)
        var remaining = fraction * total
        for index in lengths.indices {
            let length = lengths[index]
            if remaining <= length || index == lengths.count - 1 {
                let t = length > 0 ? min(1,max(0,remaining / length)) : 0
                let a = points[index], b = points[index + 1]
                let direction = outbound ? 1.0 : -1.0
                return .init(x: a.x + (b.x-a.x)*t, z: a.z + (b.z-a.z)*t,
                             heading: atan2(-(b.x-a.x)*direction, -(b.z-a.z)*direction), fraction: fraction)
            }
            remaining -= length
        }
        return .init(x: points[0].x,z: points[0].z,heading: 0,fraction: 0)
    }
}
