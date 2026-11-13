import XCTest
@testable import TaktCore

final class CityRouteTests: XCTestCase {
    func testZurichRoutesUseDistinctGeographicPathsWithoutChangingOtherCities() {
        for route in Catalog.routes {
            let points = route.points(in: "zurich")
            XCTAssertGreaterThan(points.count, 1, route.id)
            XCTAssertNotEqual(points, route.points, "Zürich must not silently use the old grid")
            XCTAssertEqual(route.points(in: "bern"), route.points)
            XCTAssertTrue(points.allSatisfy { $0.x.isFinite && $0.z.isFinite && abs($0.x) < 90 && abs($0.z) < 90 })
            XCTAssertFalse(route.stopNames(in: "zurich").isEmpty)
        }
    }

    func testImportedRoadRoutesFollowManySurveyedBendsAndRemainContinuous() {
        for id in ["b31", "b33", "t4", "t8"] {
            let points = Catalog.route(id)!.points(in: "zurich")
            XCTAssertGreaterThan(points.count, 50, "Must preserve the real road alignment")
            let distances = zip(points, points.dropFirst()).map { hypot($1.x - $0.x, $1.z - $0.z) }
            XCTAssertGreaterThan(distances.reduce(0, +), 10, "City routes span more than one kilometre")
            XCTAssertLessThan(distances.max()!, 20, "Straight simplified roads may span 1.5km; reject city-wide jumps")
            for phase in [0.0, 0.18, 0.5, 0.82, 1, 1.5, 2] {
                let p = RouteMotion.pose(points: points, phase: phase)
                XCTAssertTrue(zip(points, points.dropFirst()).contains { a, b in
                    abs(hypot(p.x-a.x, p.z-a.z) + hypot(p.x-b.x, p.z-b.z) - hypot(b.x-a.x, b.z-a.z)) < 0.0001
                })
            }
        }
    }

    func testFictionalExpansionRoutesAreLabelled() {
        for id in ["m1", "c1", "a1"] {
            XCTAssertTrue(Catalog.route(id)!.spatialNote(in: "zurich").hasPrefix("Fiktiv"))
        }
        XCTAssertTrue(Catalog.route("l1")!.spatialNote(in: "zurich").contains("angenäherte"))
    }
}
