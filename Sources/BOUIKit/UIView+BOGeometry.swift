#if canImport(UIKit)
import UIKit

/// 写之前先判等的便利层。
///
/// 为什么要判等而不是直接写：
/// - 重复写同一个 `frame` 会打断在飞的 `UIViewPropertyAnimator`（它以当前 presentation 状态为基准接管）；
/// - 给 `UIScrollView` 写 `frame` 会顺带重算并夹取 `contentOffset`，正在跟手拖动时会顿一下；
/// - 逐帧驱动的路径（`CADisplayLink` 刷调试框、拖拽中跟手布局）绝大多数帧几何其实没变，白写一次就白跑一次布局。
///
/// 默认容差 0.5pt：亚像素抖动不算变化。

/// 判等容差默认值（pt）。
public let boGeometryDefaultTolerance: CGFloat = 0.5

public extension CGPoint {
    /// 两点近似相等。
    func bo_isApproximatelyEqual(
        to other: CGPoint,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        abs(x - other.x) <= tolerance && abs(y - other.y) <= tolerance
    }
}

public extension CGSize {
    /// 两个尺寸近似相等。
    func bo_isApproximatelyEqual(
        to other: CGSize,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        abs(width - other.width) <= tolerance && abs(height - other.height) <= tolerance
    }
}

public extension CGRect {
    /// 两个矩形近似相等（原点与尺寸分别判定）。
    func bo_isApproximatelyEqual(
        to other: CGRect,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        abs(minX - other.minX) <= tolerance
            && abs(minY - other.minY) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

public extension UIEdgeInsets {
    /// 两组 inset 近似相等。
    func bo_isApproximatelyEqual(
        to other: UIEdgeInsets,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        abs(top - other.top) <= tolerance
            && abs(left - other.left) <= tolerance
            && abs(bottom - other.bottom) <= tolerance
            && abs(right - other.right) <= tolerance
    }
}

public extension UIView {
    /// `frame` 没变就不写。返回值表示这次是否真的写了。
    @discardableResult
    func bo_setFrame(
        _ frame: CGRect,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        guard !self.frame.bo_isApproximatelyEqual(to: frame, tolerance: tolerance) else { return false }
        self.frame = frame
        return true
    }

    /// `bounds` 没变就不写。返回值表示这次是否真的写了。
    @discardableResult
    func bo_setBounds(
        _ bounds: CGRect,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        guard !self.bounds.bo_isApproximatelyEqual(to: bounds, tolerance: tolerance) else { return false }
        self.bounds = bounds
        return true
    }

    /// `center` 没变就不写。返回值表示这次是否真的写了。
    @discardableResult
    func bo_setCenter(
        _ center: CGPoint,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        guard !self.center.bo_isApproximatelyEqual(to: center, tolerance: tolerance) else { return false }
        self.center = center
        return true
    }
}

public extension UIScrollView {
    /// 当前 inset 下 `contentOffset.y` 的合法上限（= 内容底边对齐可见区底边）。
    var bo_maximumContentOffsetY: CGFloat {
        let minimum = -adjustedContentInset.top
        return max(minimum, contentSize.height + adjustedContentInset.bottom - bounds.height)
    }

    /// 当前 inset 下 `contentOffset.x` 的合法上限。
    var bo_maximumContentOffsetX: CGFloat {
        let minimum = -adjustedContentInset.left
        return max(minimum, contentSize.width + adjustedContentInset.right - bounds.width)
    }

    /// 是否已经滚到底。已在底部时不必再调 `setContentOffset` / `scrollToRow`：
    /// 那会打断在飞的减速动画，也会白跑一次布局。
    func bo_isScrolledToBottom(tolerance: CGFloat = boGeometryDefaultTolerance) -> Bool {
        contentOffset.y >= bo_maximumContentOffsetY - tolerance
    }

    /// 是否已经滚到顶。
    func bo_isScrolledToTop(tolerance: CGFloat = boGeometryDefaultTolerance) -> Bool {
        contentOffset.y <= -adjustedContentInset.top + tolerance
    }

    /// `contentOffset` 没变就不写。返回值表示这次是否真的写了。
    @discardableResult
    func bo_setContentOffset(
        _ offset: CGPoint,
        animated: Bool = false,
        tolerance: CGFloat = boGeometryDefaultTolerance
    ) -> Bool {
        guard !contentOffset.bo_isApproximatelyEqual(to: offset, tolerance: tolerance) else { return false }
        setContentOffset(offset, animated: animated)
        return true
    }
}

#endif
