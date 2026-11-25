import CoreGraphics
import Testing
@testable import ExplorerCore

@Suite struct WindowTilingTests {
    @Test func halvesCoverTheAreaWithoutOverlap() {
        let area = CGRect(x: 0, y: 25, width: 1511, height: 900)
        let (left, right) = WindowTiling.halves(of: area)
        #expect(left == CGRect(x: 0, y: 25, width: 755, height: 900))
        #expect(right == CGRect(x: 755, y: 25, width: 756, height: 900))
        #expect(left.union(right) == area)
    }

    @Test func halvesFollowASecondScreen() {
        let (left, right) = WindowTiling.halves(of: CGRect(x: -1920, y: 0, width: 1920, height: 1080))
        #expect(left.minX == -1920)
        #expect(right.minX == -960)
        #expect(right.maxX == 0)
    }

    @Test func neighbourIsTheNextTabOrThePreviousForTheLast() {
        #expect(WindowTiling.neighbour(of: 0, count: 3) == 1)
        #expect(WindowTiling.neighbour(of: 1, count: 3) == 2)
        #expect(WindowTiling.neighbour(of: 2, count: 3) == 1)
        #expect(WindowTiling.neighbour(of: 0, count: 1) == nil)
        #expect(WindowTiling.neighbour(of: 3, count: 3) == nil)
    }
}
