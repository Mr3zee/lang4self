import AppKit
import XCTest
@testable import Lang4Self

@MainActor
final class OverlayScrollbarStylerTests: XCTestCase {
    func testStylesEveryNestedScrollViewAsSmallOverlay() {
        let rootView = NSView()
        let container = NSView()
        let firstScrollView = makeLegacyScrollView()
        let secondScrollView = makeLegacyScrollView()
        rootView.addSubview(firstScrollView)
        rootView.addSubview(container)
        container.addSubview(secondScrollView)

        OverlayScrollbarStyler.styleScrollViews(in: rootView)

        for scrollView in [firstScrollView, secondScrollView] {
            XCTAssertEqual(scrollView.scrollerStyle, .overlay)
            XCTAssertEqual(scrollView.verticalScroller?.controlSize, .small)
            XCTAssertEqual(scrollView.horizontalScroller?.controlSize, .small)
        }
    }

    func testOverlayScrollbarsDoNotChangeContentLayoutWhenShown() {
        let scrollView = makeLegacyScrollView()
        scrollView.frame = NSRect(x: 0, y: 0, width: 200, height: 200)
        OverlayScrollbarStyler.styleScrollViews(in: scrollView)

        scrollView.hasVerticalScroller = false
        scrollView.tile()
        let contentSizeWithoutScrollbar = scrollView.contentSize

        scrollView.hasVerticalScroller = true
        scrollView.tile()

        XCTAssertEqual(scrollView.contentSize, contentSizeWithoutScrollbar)
    }

    private func makeLegacyScrollView() -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.scrollerStyle = .legacy
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        return scrollView
    }
}
