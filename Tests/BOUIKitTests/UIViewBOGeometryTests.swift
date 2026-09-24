#if canImport(UIKit)
import XCTest
import UIKit
@testable import BOUIKit

/// `UIView+BOGeometry` 的行为约定：判等容差、不变就不写、滚动位置判定。
@MainActor
final class UIViewBOGeometryTests: XCTestCase {

    func testSetFrameSkipsWriteWithinTolerance() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 100, height: 50))
        XCTAssertFalse(view.bo_setFrame(CGRect(x: 0.2, y: -0.3, width: 100.4, height: 50)))
        XCTAssertEqual(view.frame, CGRect(x: 0, y: 0, width: 100, height: 50), "容差内不该写入")

        XCTAssertTrue(view.bo_setFrame(CGRect(x: 0, y: 0, width: 100, height: 60)))
        XCTAssertEqual(view.frame.height, 60)
    }

    func testSetCenterAndBoundsReportWhetherTheyWrote() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        XCTAssertFalse(view.bo_setCenter(CGPoint(x: 20.4, y: 20)))
        XCTAssertTrue(view.bo_setCenter(CGPoint(x: 100, y: 20)))
        XCTAssertEqual(view.center.x, 100)

        XCTAssertFalse(view.bo_setBounds(CGRect(x: 0, y: 0, width: 40.3, height: 40)))
        XCTAssertTrue(view.bo_setBounds(CGRect(x: 0, y: 0, width: 80, height: 40)))
        XCTAssertEqual(view.bounds.width, 80)
    }

    func testCustomToleranceIsHonored() {
        let view = UIView(frame: .zero)
        XCTAssertFalse(view.bo_setFrame(CGRect(x: 3, y: 0, width: 0, height: 0), tolerance: 4))
        XCTAssertTrue(view.bo_setFrame(CGRect(x: 3, y: 0, width: 0, height: 0), tolerance: 1))
    }

    func testScrollPositionJudgesUseContentInset() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 300)
        scrollView.contentInset = UIEdgeInsets(top: 10, left: 0, bottom: 20, right: 0)

        XCTAssertEqual(scrollView.bo_maximumContentOffsetY, 300 + 20 - 100)
        XCTAssertFalse(scrollView.bo_isScrolledToBottom())
        XCTAssertFalse(scrollView.bo_isScrolledToTop(), "offset 0 时内容顶部还差一个 top inset 才到位")

        scrollView.contentOffset = CGPoint(x: 0, y: -10)
        XCTAssertTrue(scrollView.bo_isScrolledToTop())

        scrollView.contentOffset = CGPoint(x: 0, y: scrollView.bo_maximumContentOffsetY)
        XCTAssertTrue(scrollView.bo_isScrolledToBottom())
        XCTAssertFalse(scrollView.bo_isScrolledToTop())
    }

    func testMaximumContentOffsetNeverGoesBelowMinimum() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 50, height: 20)
        scrollView.contentInset = UIEdgeInsets(top: 30, left: 40, bottom: 0, right: 0)

        XCTAssertEqual(scrollView.bo_maximumContentOffsetY, -30, "内容不足一屏时上限退化为顶部 inset")
        XCTAssertEqual(scrollView.bo_maximumContentOffsetX, -40)
    }

    func testSetContentOffsetSkipsWriteWithinTolerance() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 400)

        XCTAssertTrue(scrollView.bo_setContentOffset(CGPoint(x: 0, y: 120)))
        XCTAssertEqual(scrollView.contentOffset.y, 120)
        XCTAssertFalse(scrollView.bo_setContentOffset(CGPoint(x: 0, y: 120.3)))
    }

    func testContentBottomVisibleIgnoresBottomInset() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 300)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 120, right: 0)

        // 内容底边刚好对齐可见区底边：严格口径还差一个 bottom inset，宽松口径已经到底。
        scrollView.contentOffset = CGPoint(x: 0, y: 200)
        XCTAssertFalse(scrollView.bo_isScrolledToBottom())
        XCTAssertTrue(scrollView.bo_isContentBottomVisible())

        // 继续把 inset 空白也滑出来，两个口径都成立。
        scrollView.contentOffset = CGPoint(x: 0, y: scrollView.bo_maximumContentOffsetY)
        XCTAssertTrue(scrollView.bo_isScrolledToBottom())
        XCTAssertTrue(scrollView.bo_isContentBottomVisible())

        // 还差一屏时两个口径都不成立。
        scrollView.contentOffset = CGPoint(x: 0, y: 50)
        XCTAssertFalse(scrollView.bo_isScrolledToBottom())
        XCTAssertFalse(scrollView.bo_isContentBottomVisible())
    }

    func testContentBottomVisibleStaysTrueAfterBottomInsetGrows() {
        let scrollView = UIScrollView(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        scrollView.contentSize = CGSize(width: 100, height: 300)
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 20, right: 0)
        scrollView.contentOffset = CGPoint(x: 0, y: scrollView.bo_maximumContentOffsetY)
        XCTAssertTrue(scrollView.bo_isScrolledToBottom())

        // 贴底之后把 bottom inset 调大：contentOffset 不会自己跟着走。
        scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 60, right: 0)
        XCTAssertFalse(scrollView.bo_isScrolledToBottom(), "严格口径此时会认为没到底")
        XCTAssertTrue(scrollView.bo_isContentBottomVisible(), "内容底边仍在可见区内")
    }
}

#endif
