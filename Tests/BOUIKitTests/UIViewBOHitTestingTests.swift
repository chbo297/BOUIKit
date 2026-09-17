#if canImport(UIKit)
import XCTest
import UIKit
@testable import BOUIKit

/// `UIView+BOHitTesting` 的行为约定：外扩/内缩、跳过自身、自定义判定、hitTest 包装。
@MainActor
final class UIViewBOHitTestingTests: XCTestCase {

    private func makeContainerWithChild() -> (container: UIView, child: UIView) {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 200, height: 100))
        let child = UIView(frame: CGRect(x: 50, y: 20, width: 100, height: 60))
        container.addSubview(child)
        return (container, child)
    }

    func testDefaultsAreInactive() {
        let view = UIView()
        XCTAssertEqual(view.bo_hitAreaOutsets, .zero)
        XCTAssertFalse(view.bo_skipsSelfInHitTest)
        XCTAssertNil(view.bo_pointInsideJudge)
        XCTAssertNil(view.bo_hitTestHook)
    }

    func testHitAreaOutsetsExpandAndShrink() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        let outsidePoint = CGPoint(x: -6, y: 20)
        XCTAssertFalse(view.point(inside: outsidePoint, with: nil))

        view.bo_hitAreaOutsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)
        XCTAssertTrue(view.point(inside: outsidePoint, with: nil), "正值应扩大响应范围")

        view.bo_hitAreaOutsets = UIEdgeInsets(top: -15, left: -15, bottom: -15, right: -15)
        XCTAssertTrue(view.point(inside: CGPoint(x: 20, y: 20), with: nil), "中心仍在缩小后的矩形内")
        XCTAssertFalse(view.point(inside: CGPoint(x: 5, y: 20), with: nil), "负值应缩小响应范围")

        view.bo_hitAreaOutsets = UIEdgeInsets(top: -25, left: -25, bottom: -25, right: -25)
        XCTAssertFalse(view.point(inside: CGPoint(x: 20, y: 20), with: nil), "缩到宽高非正时不再响应")

        view.bo_hitAreaOutsets = .zero
        XCTAssertTrue(view.point(inside: CGPoint(x: 20, y: 20), with: nil), ".zero 回退原实现")
        XCTAssertFalse(view.point(inside: outsidePoint, with: nil))
    }

    /// 跳过自身：命中自己时返回 nil，命中子视图不受影响。
    func testSkipsSelfInHitTestKeepsSubviewsResponsive() {
        let (container, child) = makeContainerWithChild()
        let selfPoint = CGPoint(x: 10, y: 10)
        let childPoint = CGPoint(x: 100, y: 50)

        XCTAssertTrue(container.hitTest(selfPoint, with: nil) === container)
        XCTAssertTrue(container.hitTest(childPoint, with: nil) === child)

        container.bo_skipsSelfInHitTest = true
        XCTAssertNil(container.hitTest(selfPoint, with: nil), "命中自己应穿透")
        XCTAssertTrue(container.hitTest(childPoint, with: nil) === child, "子视图仍要能响应")

        container.bo_skipsSelfInHitTest = false
        XCTAssertTrue(container.hitTest(selfPoint, with: nil) === container, "关掉后恢复默认")
    }

    /// 跳过自身与外扩组合：扩大区域里的触点也不会被自己接住。
    func testSkipsSelfCombinesWithOutsets() {
        let (container, child) = makeContainerWithChild()
        container.bo_hitAreaOutsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        container.bo_skipsSelfInHitTest = true

        XCTAssertTrue(container.point(inside: CGPoint(x: -10, y: -10), with: nil))
        XCTAssertNil(container.hitTest(CGPoint(x: -10, y: -10), with: nil))
        XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 50), with: nil) === child)
    }

    func testPointInsideJudgeTakesPrecedence() {
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 40, height: 40))
        view.bo_hitAreaOutsets = UIEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        view.bo_pointInsideJudge = { _, point, _ in point.x < 0 ? false : nil }

        XCTAssertFalse(view.point(inside: CGPoint(x: -5, y: 20), with: nil), "非空判定优先")
        XCTAssertTrue(view.point(inside: CGPoint(x: 45, y: 20), with: nil), "nil 继续走 outsets")

        view.bo_pointInsideJudge = nil
        XCTAssertTrue(view.point(inside: CGPoint(x: -5, y: 20), with: nil))
    }

    /// hook 可以改写结果，并通过 original 同步转发原实现而不递归。
    func testHitTestHookWrapsOriginal() {
        let (container, child) = makeContainerWithChild()
        let replacement = UIView(frame: container.bounds)
        var forwardedResults: [UIView?] = []

        container.bo_hitTestHook = { view, point, event, original in
            let result = original(point, event)
            forwardedResults.append(result)
            return result === view ? replacement : result
        }

        XCTAssertTrue(container.hitTest(CGPoint(x: 10, y: 10), with: nil) === replacement)
        XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 50), with: nil) === child)
        XCTAssertEqual(forwardedResults.count, 2)

        // 跳过自身在 hook 之后生效：hook 把结果换回自己时依然被过滤掉。
        container.bo_skipsSelfInHitTest = true
        container.bo_hitTestHook = { view, _, _, _ in view }
        XCTAssertNil(container.hitTest(CGPoint(x: 100, y: 50), with: nil))
    }

    /// 全部配置清空后不应残留状态。
    func testClearingAllConfigurationRestoresOriginalBehavior() {
        let (container, child) = makeContainerWithChild()
        container.bo_hitAreaOutsets = UIEdgeInsets(top: 5, left: 5, bottom: 5, right: 5)
        container.bo_skipsSelfInHitTest = true
        container.bo_pointInsideJudge = { _, _, _ in true }
        container.bo_hitTestHook = { _, point, event, original in original(point, event) }

        container.bo_hitAreaOutsets = .zero
        container.bo_skipsSelfInHitTest = false
        container.bo_pointInsideJudge = nil
        container.bo_hitTestHook = nil

        XCTAssertEqual(container.bo_hitAreaOutsets, .zero)
        XCTAssertFalse(container.bo_skipsSelfInHitTest)
        XCTAssertNil(container.bo_pointInsideJudge)
        XCTAssertNil(container.bo_hitTestHook)
        XCTAssertTrue(container.hitTest(CGPoint(x: 10, y: 10), with: nil) === container)
        XCTAssertTrue(container.hitTest(CGPoint(x: 100, y: 50), with: nil) === child)
        XCTAssertFalse(container.point(inside: CGPoint(x: -3, y: -3), with: nil))
    }
}
#endif
