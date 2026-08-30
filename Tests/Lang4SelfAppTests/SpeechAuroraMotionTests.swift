import XCTest
@testable import Lang4Self

final class SpeechAuroraMotionTests: XCTestCase {
    func testReduceMotionPinsAuroraToItsInitialPhase() {
        let date = Date(timeIntervalSinceReferenceDate: 123_456)

        XCTAssertEqual(SpeechAuroraMotion.phase(at: date, reduceMotion: true), 0)
        XCTAssertEqual(SpeechAuroraMotion.phase(at: date, reduceMotion: false), 123_456)
    }

    func testAuroraOffsetCompletesASmoothLoop() {
        let start = SpeechAuroraMotion.offset(
            at: 0,
            period: 40,
            xAmplitude: 18,
            yAmplitude: 10,
            initialAngle: 0
        )
        let quarter = SpeechAuroraMotion.offset(
            at: 10,
            period: 40,
            xAmplitude: 18,
            yAmplitude: 10,
            initialAngle: 0
        )
        let end = SpeechAuroraMotion.offset(
            at: 40,
            period: 40,
            xAmplitude: 18,
            yAmplitude: 10,
            initialAngle: 0
        )

        XCTAssertEqual(start.width, 18, accuracy: 0.001)
        XCTAssertEqual(start.height, 0, accuracy: 0.001)
        XCTAssertEqual(quarter.width, 0, accuracy: 0.001)
        XCTAssertEqual(quarter.height, 10, accuracy: 0.001)
        XCTAssertEqual(end.width, start.width, accuracy: 0.001)
        XCTAssertEqual(end.height, start.height, accuracy: 0.001)
    }
}
