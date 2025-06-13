import XCTest
@testable import DynaVibe

final class AxisRangeTests: XCTestCase {
    func testNiceAxisRangeAndTicksSimpleRange() {
        let viewModel = AccelerationViewModel()
        let result = viewModel.niceAxisRangeAndTicks(min: 0, max: 10, maxTicks: 5)
        XCTAssertEqual(result.tickSpacing, 2, accuracy: 0.0001)
        XCTAssertEqual(result.niceMin, 0, accuracy: 0.0001)
        XCTAssertEqual(result.niceMax, 10, accuracy: 0.0001)
        XCTAssertEqual(result.ticks, [0, 2, 4, 6, 8, 10])
    }
}
