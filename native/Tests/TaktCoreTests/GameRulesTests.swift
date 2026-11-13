import XCTest
@testable import TaktCore

final class GameRulesTests: XCTestCase {
    private let day = "2026-11-13"
    private func advance(_ state: inout GameState, seconds: Double, step: Double = 1) {
        var remaining = seconds
        while remaining > 0.000001 {
            let dt = min(step,remaining)
            GameRules.advance(&state, by: dt, day: day)
            remaining -= dt
        }
    }
    func testFirstMountainSessionUnlocksTheValley() throws {
        var s = GameState()
        XCTAssertEqual(s.currentLines.map(\.id), ["b31"])
        try GameRules.apply(.buy("b33"), to: &s, day: day)
        XCTAssertEqual(s.coins, 650)
        try GameRules.apply(.claim("second"), to: &s, day: day)
        XCTAssertEqual(s.coins, 1300)
        XCTAssertEqual(s.level, 2)
        XCTAssertNotNil(GameRules.unlockReason(route: Catalog.route("t4")!, state: s))
        XCTAssertThrowsError(try GameRules.apply(.visit("altdorf"), to: &s, day: day))
        advance(&s, seconds: 300)
        let beforeVisit = s.coins
        try GameRules.apply(.visit("altdorf"), to: &s, day: day)
        XCTAssertEqual(s.coins, beforeVisit - Catalog.city("altdorf").price)
        XCTAssertEqual(s.cityID, "altdorf")
        XCTAssertEqual(s.currentLines.map(\.id), ["b31"])
    }
    func testRejectedActionsAreAtomic() {
        let invalid: [GameAction] = [.buy("made-up"),.buy("t4"),.buy("b31"),.claim("second"),.upgrade("missing"),.visit("tokyo")]
        for action in invalid {
            var s = GameState(), original = s
            XCTAssertThrowsError(try GameRules.apply(action,to: &s,day: day))
            XCTAssertEqual(s,original)
            original.coins = 0; s = original
            XCTAssertThrowsError(try GameRules.apply(.buy("b33"),to: &s,day: day))
            XCTAssertEqual(s,original)
        }
    }
    func testRewardCannotBeClaimedTwice() throws {
        var s = GameState()
        try GameRules.apply(.buy("b33"),to: &s,day: day)
        try GameRules.apply(.claim("second"),to: &s,day: day)
        let original = s
        XCTAssertThrowsError(try GameRules.apply(.claim("second"),to: &s,day: day))
        XCTAssertEqual(s,original)
    }
    func testTripsPayOnlyAfterArrival() {
        var s = GameState()
        advance(&s,seconds: 13)
        XCTAssertEqual(s.passengers,0)
        advance(&s,seconds: 1)
        XCTAssertEqual(s.passengers,8)
        XCTAssertEqual(s.coins,1232)
        XCTAssertEqual(s.currentLines[0].carried,8)
        XCTAssertEqual(s.currentLines[0].progress,0,accuracy: 0.00001)
    }
    func testUpgradesIncreaseCapacityAndStopAtFive() throws {
        var s = GameState(); s.coins = 100000
        try GameRules.apply(.upgrade("b31"),to: &s,day: day)
        XCTAssertEqual(s.coins,99600)
        advance(&s,seconds: 14)
        XCTAssertEqual(s.passengers,16)
        for _ in 0..<3 { try GameRules.apply(.upgrade("b31"),to: &s,day: day) }
        XCTAssertEqual(s.owned("b31")?.tier,5)
        XCTAssertThrowsError(try GameRules.apply(.upgrade("b31"),to: &s,day: day))
    }
    func testCitiesRemainIndependentAndBothEarn() throws {
        var s = GameState(); s.coins = 10000; s.xp = GameState.xpNeeded(for: 3)
        try GameRules.apply(.visit("altdorf"),to: &s,day: day)
        XCTAssertEqual(s.coins,7200)
        try GameRules.apply(.buy("b33"),to: &s,day: day)
        XCTAssertEqual(s.networks["andermatt"]?.lines.count,1)
        XCTAssertEqual(s.networks["altdorf"]?.lines.count,2)
        advance(&s,seconds: 14)
        XCTAssertEqual(s.passengers,16)
        let coins = s.coins
        try GameRules.apply(.visit("andermatt"),to: &s,day: day)
        XCTAssertEqual(s.coins,coins)
    }
    func testDifferentFrameSizesKeepRewardsConsistentAcrossEvents() throws {
        var a = GameState()
        try GameRules.apply(.buy("b33"),to: &a,day: day)
        var b = a, c = a
        advance(&a,seconds: 240,step: 1)
        advance(&b,seconds: 240,step: 3)
        advance(&c,seconds: 240,step: 0.25)
        XCTAssertEqual(a.coins,b.coins); XCTAssertEqual(a.coins,c.coins)
        XCTAssertEqual(a.passengers,b.passengers); XCTAssertEqual(a.passengers,c.passengers)
        XCTAssertEqual(a.xp,b.xp); XCTAssertEqual(a.xp,c.xp)
    }
    func testTemporaryEventStartsAndExpires() {
        var s = GameState()
        advance(&s,seconds: 120)
        XCTAssertEqual(s.event?.endsAt,155)
        let coins = s.coins
        advance(&s,seconds: 6)
        XCTAssertEqual(s.coins-coins,48)
        advance(&s,seconds: 30)
        XCTAssertNil(s.event)
    }
    func testDailyRewardSurvivesSaveAndResetsNextDay() throws {
        var s = GameState(); s.dailyDate = day; s.dailyEarned = 5000
        let id = "daily-"+day
        try GameRules.apply(.claim(id),to: &s,day: day)
        s = try SaveCodec.decode(SaveCodec.encode(s))
        XCTAssertThrowsError(try GameRules.apply(.claim(id),to: &s,day: day))
        GameRules.advance(&s,by: 1,day: "2026-11-14")
        XCTAssertEqual(s.dailyEarned,0)
        XCTAssertFalse(GameRules.quests(s,day: "2026-11-14").last!.ready)
    }
    func testTwoHourActiveSwissProgressionHasNoSoftlockOrInstantCompletion() {
        var s = GameState()
        var firstArrival: [String: Double] = [:]
        for _ in 0..<1440 {
            GameRules.advance(&s, by: 5, day: day)
            for q in GameRules.quests(s, day: day) where q.ready && !s.claimed.contains(q.id) {
                try? GameRules.apply(.claim(q.id), to: &s, day: day)
            }
            for route in Catalog.routes(in: s.cityID) {
                try? GameRules.apply(.buy(route.id), to: &s, day: day)
            }
            // An active player reinvests in each local network before expanding.
            for line in s.currentLines where line.tier < 5 {
                try? GameRules.apply(.upgrade(line.id), to: &s, day: day)
            }
            for city in Catalog.cities where s.networks[city.id] == nil {
                try? GameRules.apply(.visit(city.id), to: &s, day: day)
                if s.networks[city.id] != nil { firstArrival[city.id] = s.seconds }
            }
        }
        XCTAssertEqual(s.networks.count, 8)
        XCTAssertTrue(Catalog.playableKinds.allSatisfy { s.ownsKind($0) })
        XCTAssertGreaterThan(firstArrival["geneva"] ?? 0, 30 * 60)
        XCTAssertLessThanOrEqual(firstArrival["geneva"] ?? .infinity, 120 * 60)
        XCTAssertTrue(s.isValid)
    }
    func testSaveRoundTripAndInvalidValues() throws {
        var s = GameState(); try GameRules.apply(.buy("b33"),to: &s,day: day)
        s.settings.night = true; advance(&s,seconds: 23)
        XCTAssertEqual(try SaveCodec.decode(SaveCodec.encode(s)),s)
        XCTAssertThrowsError(try SaveCodec.decode(Data("broken".utf8)))
        s.coins = -1
        XCTAssertThrowsError(try SaveCodec.decode(SaveCodec.encode(s)))
        s.coins = 1; s.networks["andermatt"]!.lines[0].progress = 10000
        XCTAssertThrowsError(try SaveCodec.decode(SaveCodec.encode(s)))
    }
    func testUnknownAndDuplicateSavedRoutesAreRejected() throws {
        var s = GameState(); s.networks["andermatt"]!.lines.append(OwnedLine(id: "b31"))
        XCTAssertFalse(s.isValid)
        s = GameState(); s.networks["andermatt"]!.lines = [OwnedLine(id: "unknown")]
        XCTAssertFalse(s.isValid)
        s = GameState(); s.cityID = "unknown"
        XCTAssertFalse(s.isValid)
    }
    func testInvalidElapsedTimeDoesNotAdvanceSimulation() {
        for dt in [0.0,-1,Double.nan,Double.infinity] {
            var s = GameState(); let before = s
            GameRules.advance(&s,by: dt,day: day)
            XCTAssertEqual(s,before)
        }
    }
    func testSequentialRegionsCannotBeSkippedEvenWithMoneyAndLevel() throws {
        var s = GameState(); s.coins = 10_000_000; s.xp = 100_000
        let before = s
        XCTAssertThrowsError(try GameRules.apply(.visit("zurich"), to: &s, day: day))
        XCTAssertEqual(s, before)
        for city in Catalog.cities.dropFirst() {
            XCTAssertNil(s.regionUnlockReason(cityID: city.id))
            try GameRules.apply(.visit(city.id), to: &s, day: day)
            XCTAssertEqual(s.currentLines.map(\.id), ["b31"])
        }
        XCTAssertTrue(s.isValid)
    }
    func testLocalTransportPrerequisitesAndWrongRegionRejectAtomically() throws {
        var s = GameState(); s.coins = 10_000_000; s.xp = 100_000
        for id in ["t4", "s12", "ic1", "a1", "m1", "l1", "c1"] {
            let before = s
            XCTAssertThrowsError(try GameRules.apply(.buy(id), to: &s, day: day))
            XCTAssertEqual(s, before)
        }
        for city in Catalog.cities.dropFirst().prefix(4) { try GameRules.apply(.visit(city.id), to: &s, day: day) }
        for id in ["s12", "ic1", "a1"] {
            let before = s
            XCTAssertThrowsError(try GameRules.apply(.buy(id), to: &s, day: day)); XCTAssertEqual(s,before)
        }
        for id in ["t4", "s12", "ic1", "a1"] {
            XCTAssertNil(GameRules.unlockReason(route: Catalog.route(id)!, state: s))
            try GameRules.apply(.buy(id), to: &s, day: day)
        }
        XCTAssertTrue(s.isValid)
    }
    func testV2MigrationKeepsSwissAssetsAndRefundsRetiredAssets() throws {
        var old = GameState(); old.version = 2; old.cityID = "paris"; old.coins = 1234
        old.xp = 900; old.passengers = 789; old.settings.night = true
        var retired = OwnedLine(id: "m1"); retired.tier = 3; retired.carried = 99
        var bus = OwnedLine(id: "b33"); bus.tier = 2; bus.progress = 4
        old.networks = ["zurich": CityNetwork(lines: [OwnedLine(id: "b31"), bus, retired]), "paris": CityNetwork(lines: [bus])]
        let migrated = try SaveCodec.decode(SaveCodec.encode(old))
        let metro = Catalog.route("m1")!, busRoute = Catalog.route("b33")!
        let refund = 6500 + metro.price + metro.upgradePrice(tier: 1) + metro.upgradePrice(tier: 2) + busRoute.price + busRoute.upgradePrice(tier: 1)
        XCTAssertEqual(migrated.coins, old.coins + refund)
        XCTAssertEqual(migrated.xp, old.xp); XCTAssertEqual(migrated.passengers, old.passengers)
        XCTAssertEqual(migrated.settings, old.settings)
        XCTAssertEqual(migrated.version,3); XCTAssertEqual(migrated.cityID,"andermatt")
        XCTAssertNotNil(migrated.networks["zurich"]); XCTAssertNil(migrated.networks["paris"])
        XCTAssertEqual(migrated.networks["zurich"]?.lines.first { $0.id == "b33" }, bus)
        XCTAssertTrue(migrated.isValid)
        XCTAssertEqual(try SaveCodec.decode(SaveCodec.encode(migrated)), migrated)
        old.networks["paris"]!.lines[0].tier = 100
        XCTAssertThrowsError(try SaveCodec.decode(SaveCodec.encode(old)))
    }
    func testV3SaveRejectsMissingPredecessorRegion() throws {
        var s = GameState()
        s.networks["zurich"] = CityNetwork()
        XCTAssertFalse(s.isValid)
        XCTAssertThrowsError(try SaveCodec.decode(SaveCodec.encode(s)))
    }
    func testV3SaveRejectsRegionIncompatibleLines() throws {
        var s = GameState(); s.networks["andermatt"]!.lines.append(OwnedLine(id: "a1"))
        XCTAssertFalse(s.isValid)
        XCTAssertThrowsError(try SaveCodec.decode(SaveCodec.encode(s)))
    }
    func testVehiclesVisitBothTerminalsAndStayOnTheirPredefinedSegments() {
        for route in Catalog.routes {
            let start = RouteMotion.pose(points: route.points,phase: 0)
            let end = RouteMotion.pose(points: route.points,phase: 1)
            let returned = RouteMotion.pose(points: route.points,phase: 2)
            XCTAssertEqual(start.x,route.points.first!.x,accuracy: 0.00001)
            XCTAssertEqual(end.z,route.points.last!.z,accuracy: 0.00001)
            XCTAssertEqual(returned.x,start.x,accuracy: 0.00001)
            for phase in stride(from: 0.0,through: 2.0,by: 0.025) {
                let p = RouteMotion.pose(points: route.points,phase: phase)
                let onPath = zip(route.points,route.points.dropFirst()).contains { a,b in
                    abs(hypot(p.x-a.x,p.z-a.z)+hypot(p.x-b.x,p.z-b.z)-hypot(b.x-a.x,b.z-a.z)) < 0.0001
                }
                XCTAssertTrue(onPath,"\(route.id) left its route")
            }
        }
    }
}
