#if canImport(UIKit)
import ObjectiveC.runtime
import UIKit

public typealias BOViewPointInsideJudge = (
    _ bounds: CGRect,
    _ point: CGPoint,
    _ event: UIEvent?
) -> Bool?

public typealias BOViewHitTestOriginal = (
    _ point: CGPoint,
    _ event: UIEvent?
) -> UIView?

public typealias BOViewHitTestHook = (
    _ view: UIView,
    _ point: CGPoint,
    _ event: UIEvent?,
    _ original: BOViewHitTestOriginal
) -> UIView?

@MainActor
private final class BOViewHitTestingHookState: NSObject {
    var hitAreaOutsets = UIEdgeInsets.zero
    var skipsSelfInHitTest = false
    var pointInsideJudge: BOViewPointInsideJudge?
    var hitTestHook: BOViewHitTestHook?

    var isActive: Bool {
        hitAreaOutsets != .zero
            || skipsSelfInHitTest
            || pointInsideJudge != nil
            || hitTestHook != nil
    }
}

@MainActor
private enum BOViewHitTestingHookRuntime {
    static let install: Void = {
        exchange(
            #selector(UIView.point(inside:with:)),
            #selector(UIView.bo_pointInside(_:with:))
        )
        exchange(
            #selector(UIView.hitTest(_:with:)),
            #selector(UIView.bo_hitTest(_:with:))
        )
    }()

    static func installIfNeeded() {
        _ = install
    }

    private static func exchange(_ originalSelector: Selector, _ hookSelector: Selector) {
        guard
            let originalMethod = class_getInstanceMethod(UIView.self, originalSelector),
            let hookMethod = class_getInstanceMethod(UIView.self, hookSelector)
        else {
            assertionFailure("Unable to install BOUIKit UIView hit-testing hooks")
            return
        }

        method_exchangeImplementations(originalMethod, hookMethod)
    }
}

@MainActor
public extension UIView {
    /// The hook is installed lazily for `UIView` instances process-wide. A subclass that
    /// overrides hit testing without forwarding to `super` can bypass it, and expanded
    /// descendants remain constrained by the hit-testing bounds of their ancestors.
    /// Per-edge hit-area adjustment. Positive values expand and negative values shrink.
    /// `.zero` preserves the receiver's original `point(inside:with:)` implementation.
    /// A nonzero value intentionally replaces that original result with a rectangular check.
    var bo_hitAreaOutsets: UIEdgeInsets {
        get { bo_existingHitTestingHookState?.hitAreaOutsets ?? .zero }
        set {
            let resolvedOutsets = newValue.bo_finiteValuesOrZero
            guard resolvedOutsets != .zero || bo_existingHitTestingHookState != nil else {
                return
            }
            bo_updateHitTestingHookState {
                $0.hitAreaOutsets = resolvedOutsets
            }
        }
    }

    /// Skip the receiver itself during hit testing: the original `hitTest(_:with:)` runs first,
    /// and when its result is the receiver (no descendant took the touch) `nil` is returned so the
    /// touch passes through to whatever sits behind. Subviews keep responding normally.
    /// This filters the hit-test result instead of `point(inside:with:)`, because reporting the
    /// point as outside would also stop UIKit from descending into the subviews.
    /// Applied after `bo_hitTestHook`, so a hook returning the receiver is skipped as well.
    var bo_skipsSelfInHitTest: Bool {
        get { bo_existingHitTestingHookState?.skipsSelfInHitTest ?? false }
        set {
            guard newValue || bo_existingHitTestingHookState != nil else {
                return
            }
            bo_updateHitTestingHookState {
                $0.skipsSelfInHitTest = newValue
            }
        }
    }

    /// Return `nil` to continue with `bo_hitAreaOutsets` or UIKit's original result.
    var bo_pointInsideJudge: BOViewPointInsideJudge? {
        get { bo_existingHitTestingHookState?.pointInsideJudge }
        set {
            guard newValue != nil || bo_existingHitTestingHookState != nil else {
                return
            }
            bo_updateHitTestingHookState {
                $0.pointInsideJudge = newValue
            }
        }
    }

    /// Use the supplied `original` closure synchronously to forward without recursion.
    /// Capture an owning object weakly when the hook is stored on one of its views.
    var bo_hitTestHook: BOViewHitTestHook? {
        get { bo_existingHitTestingHookState?.hitTestHook }
        set {
            guard newValue != nil || bo_existingHitTestingHookState != nil else {
                return
            }
            bo_updateHitTestingHookState {
                $0.hitTestHook = newValue
            }
        }
    }

    @objc(bo_pointInside:withEvent:)
    fileprivate dynamic func bo_pointInside(_ point: CGPoint, with event: UIEvent?) -> Bool {
        guard let state = bo_existingHitTestingHookState else {
            return bo_pointInside(point, with: event)
        }

        if let decision = state.pointInsideJudge?(bounds, point, event) {
            return decision
        }

        let outsets = state.hitAreaOutsets
        guard outsets != .zero else {
            return bo_pointInside(point, with: event)
        }

        let adjustedMinX = bounds.minX - outsets.left
        let adjustedMinY = bounds.minY - outsets.top
        let adjustedMaxX = bounds.maxX + outsets.right
        let adjustedMaxY = bounds.maxY + outsets.bottom
        guard adjustedMaxX > adjustedMinX, adjustedMaxY > adjustedMinY else {
            return false
        }
        let adjustedBounds = CGRect(
            x: adjustedMinX,
            y: adjustedMinY,
            width: adjustedMaxX - adjustedMinX,
            height: adjustedMaxY - adjustedMinY
        )
        return adjustedBounds.contains(point)
    }

    @objc(bo_hitTest:withEvent:)
    fileprivate dynamic func bo_hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard let state = bo_existingHitTestingHookState else {
            return bo_hitTest(point, with: event)
        }

        let result: UIView?
        if let hook = state.hitTestHook {
            let original: BOViewHitTestOriginal = { [weak self] forwardedPoint, forwardedEvent in
                self?.bo_hitTest(forwardedPoint, with: forwardedEvent)
            }
            result = hook(self, point, event, original)
        } else {
            result = bo_hitTest(point, with: event)
        }

        if state.skipsSelfInHitTest, result === self {
            return nil
        }
        return result
    }

    private var bo_existingHitTestingHookState: BOViewHitTestingHookState? {
        objc_getAssociatedObject(self, &BOViewHitTestingAssociatedKeys.state)
            as? BOViewHitTestingHookState
    }

    private var bo_hitTestingHookState: BOViewHitTestingHookState {
        if let state = bo_existingHitTestingHookState {
            return state
        }

        let state = BOViewHitTestingHookState()
        objc_setAssociatedObject(
            self,
            &BOViewHitTestingAssociatedKeys.state,
            state,
            .OBJC_ASSOCIATION_RETAIN_NONATOMIC
        )
        return state
    }

    private func bo_updateHitTestingHookState(
        _ update: (BOViewHitTestingHookState) -> Void
    ) {
        BOViewHitTestingHookRuntime.installIfNeeded()
        let state = bo_hitTestingHookState
        update(state)
        if !state.isActive {
            objc_setAssociatedObject(
                self,
                &BOViewHitTestingAssociatedKeys.state,
                nil,
                .OBJC_ASSOCIATION_RETAIN_NONATOMIC
            )
        }
    }
}

private enum BOViewHitTestingAssociatedKeys {
    nonisolated(unsafe) static var state: UInt8 = 0
}

private extension UIEdgeInsets {
    var bo_finiteValuesOrZero: UIEdgeInsets {
        UIEdgeInsets(
            top: top.isFinite ? top : 0,
            left: left.isFinite ? left : 0,
            bottom: bottom.isFinite ? bottom : 0,
            right: right.isFinite ? right : 0
        )
    }
}
#endif
