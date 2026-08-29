import XCTest
@testable import Lang4SelfCore

final class SpacedRepetitionSchedulerTests: XCTestCase {
    func testGoodCardGraduatesToOneDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let card = PersonalCard(german: "lernen", english: "to learn", dueAt: now)
        let result = SpacedRepetitionScheduler.reviewed(card, rating: .good, now: now)
        XCTAssertEqual(result.repetitions, 1)
        XCTAssertEqual(result.intervalDays, 1)
        XCTAssertEqual(result.dueAt.timeIntervalSince(now), 86_400, accuracy: 1)
    }

    func testAgainCountsLapseAndSchedulesRelearning() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var card = PersonalCard(german: "lernen", english: "to learn", dueAt: now)
        card.repetitions = 4
        let result = SpacedRepetitionScheduler.reviewed(card, rating: .again, now: now)
        XCTAssertEqual(result.repetitions, 0)
        XCTAssertEqual(result.lapses, 1)
        XCTAssertEqual(result.dueAt.timeIntervalSince(now), 600, accuracy: 1)
    }
}
