# BOUIKit

UIKit 基础能力集合，不依赖任何业务类型、常量或资源。公开类型使用 `BO` 前缀，UIView 扩展成员与 Objective-C selector 使用 `bo_` 前缀，避免与宿主 App 命名混合。

当前包内只有一层：**UIView hit-testing 扩展**。

## 安装

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/chbo297/BOUIKit.git", from: "0.1.0")
]
```

支持 iOS 13+ / Mac Catalyst 13+。

## UIView Hit Testing

`import BOUIKit` 后，任意 `UIView` 都获得四个可选配置：

```swift
// 1. 逐边调整矩形响应范围：正值扩大、负值缩小，.zero 回退 UIKit 原实现
button.bo_hitAreaOutsets = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

// 2. 自己不接住触摸，只让子视图响应；命中自己时返回 nil，触摸穿透到下层
overlayContainer.bo_skipsSelfInHitTest = true

// 3. 自定义命中判定：返回 nil 表示不干预，继续走 outsets 或 UIKit 原实现
capsule.bo_pointInsideJudge = { bounds, point, _ in
    UIBezierPath(roundedRect: bounds, cornerRadius: bounds.height / 2).contains(point)
}

// 4. 包装 hitTest(_:with:)：用传入的 original 闭包同步转发原实现，避免递归
bar.bo_hitTestHook = { view, point, event, original in
    let hit = original(point, event)
    return hit === view ? view.inputArea : hit   // 把背景空白处的触点转交给子视图
}
```

### 语义与执行顺序

- `point(inside:with:)`：`bo_pointInsideJudge` 返回非空即采纳；返回 `nil` 时若 `bo_hitAreaOutsets != .zero` 就按外扩矩形判断，否则走 UIKit 原实现。外扩后宽或高非正时判定为不命中。
- `hitTest(_:with:)`：先执行 `bo_hitTestHook`（没有则走原实现），再由 `bo_skipsSelfInHitTest` 过滤结果——结果是自己时返回 `nil`。
- `bo_skipsSelfInHitTest` 过滤的是 hitTest 结果而不是 `point(inside:)`，否则 UIKit 会连子视图都不再下探。

### 实现方式与边界

Hook 通过 `method_exchangeImplementations` 交换 `UIView.point(inside:with:)` 与 `UIView.hitTest(_:with:)`，在**首次设置有效配置时惰性安装**，配置全部清空后连 associated object 一起移除。

需要知道的三个边界：

- 交换是进程级的，对所有 `UIView` 生效。集成方应当知晓这一点。
- 扩大后的子视图仍受祖先视图响应范围约束。
- 子类若重写 hit-testing 且不调用 `super`，会绕过本层 Hook。

所有 API 标注 `@MainActor`，只在主线程使用。

## 许可

MIT
