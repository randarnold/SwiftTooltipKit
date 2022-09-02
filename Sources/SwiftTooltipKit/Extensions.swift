//
//  Extensions.swift
//
// Copyright (c) 2022 Felix Desiderato
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

import OSLog
#if canImport(UIKit)
import UIKit

internal extension UIApplication {
    static func getTopViewController(base: UIViewController? = UIApplication.shared.keyWindow?.rootViewController) -> UIViewController? {
        if let nav = base as? UINavigationController {
            return getTopViewController(base: nav.visibleViewController)
            
        } else if let tab = base as? UITabBarController, let selected = tab.selectedViewController {
            return getTopViewController(base: selected)
            
        } else if let presented = base?.presentedViewController {
            return getTopViewController(base: presented)
        }
        return base
    }
}

internal extension Array where Element: Equatable {
    func remove(_ element: Element) -> Self {
        var mutableCopy = self
        for (index, ele) in mutableCopy.enumerated() {
            if ele == element {
                mutableCopy.remove(at: index)
                
            }
        }
        return mutableCopy
    }
}

extension UIView {
    internal var boundsOrIntrinsicContentSize: CGSize {
        return self.bounds.size != .zero ? self.bounds.size : self.intrinsicContentSize
    }
    
    /// Returns true, if the calling UIView has an active tooltip.
    /// True if there is currently a tooltip presented that has the calling view as `presentingView`.
    public var hasActiveTooltip: Bool {
        guard let activeTooltips = window?.subviews.filter({ $0 is Tooltip }),
              !activeTooltips.isEmpty else { return false }
        
        return activeTooltips.compactMap { $0 as? Tooltip }.contains(where: { $0.presentingView == self })
    }

    /// Add the tooltip as a subview
    /// - Parameter tooltip: The tooltip that will added as a subView

    fileprivate func add(tooltip: Tooltip) {

        if #available(iOS 13, *) {
            if let window = window {
                window.addSubview(tooltip)
            } else if UIApplication.shared.supportsMultipleScenes {
                os_log("Support for multiple scenes not implemented", type: .error)
            } else {
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                    guard windowScene.windows.count == 1 else {
                        os_log("Support for multiple windows not implemented", type: .error)
                        return
                    }
                    if let window = windowScene.windows.first {
                        window.addSubview(tooltip)
                    }
                }
            }
        } else {
            if let window = window {
                window.addSubview(tooltip)
            } else if let window = UIApplication.shared.keyWindow {
                window.addSubview(tooltip)
            } else {
                assertionFailure("No window available, did you set before viewDidAppear()?")
            }
        }
    }

    /// Anchor the tooltip
    /// - Parameter tooltip: The tooltip that will be anchored
    /// - Parameter orientation: The orientation of the tool tooltip
    /// - Parameter configuration: The configuration for the toolTip

    fileprivate func anchor(tooltip: Tooltip, orientation: Tooltip.Orientation, configuration: Tooltip.ToolTipConfiguration) {

        // First anchor the tooltip within the safeAreaLayoutGuide
        if let safeAreaLayoutGuide = window?.safeAreaLayoutGuide {
            NSLayoutConstraint.activate([
                tooltip.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: Tooltip.margin),
                tooltip.bottomAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.bottomAnchor, constant: -Tooltip.margin),
                tooltip.leadingAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.leadingAnchor, constant: Tooltip.margin),
                tooltip.trailingAnchor.constraint(lessThanOrEqualTo: safeAreaLayoutGuide.trailingAnchor, constant: -Tooltip.margin),
            ])
        }

        // Then anchor the tooltip to the view (self)
        switch orientation {
            case .leading, .left:
                let centerYAnchor = tooltip.centerYAnchor.constraint(equalTo: self.centerYAnchor)
                centerYAnchor.priority = .defaultHigh
                NSLayoutConstraint.activate([
                    tooltip.trailingAnchor.constraint(equalTo: self.leadingAnchor, constant: configuration.offset),
                    centerYAnchor
                ])
            case .trailing, .right:
                let centerYAnchor = tooltip.centerYAnchor.constraint(equalTo: self.centerYAnchor)
                centerYAnchor.priority = .defaultHigh
                NSLayoutConstraint.activate([
                    tooltip.leadingAnchor.constraint(equalTo: self.trailingAnchor, constant: configuration.offset),
                    centerYAnchor
                ])
            case .top:
                let centerXAnchor = tooltip.centerXAnchor.constraint(equalTo: self.centerXAnchor)
                centerXAnchor.priority = .defaultHigh
                NSLayoutConstraint.activate([
                    tooltip.bottomAnchor.constraint(equalTo: self.topAnchor, constant: configuration.offset),
                    centerXAnchor
                ])
            case .bottom:
                let centerXAnchor = tooltip.centerXAnchor.constraint(equalTo: self.centerXAnchor)
                centerXAnchor.priority = .fittingSizeLevel
                NSLayoutConstraint.activate([
                    tooltip.topAnchor.constraint(equalTo: self.bottomAnchor, constant: configuration.offset),
                    centerXAnchor
                ])
        }
    }

    public var tooltip: Tooltip? {

        for window in UIApplication.shared.windows {
            let activeTooltips = window.subviews.filter({ $0 is Tooltip })

            for case let tooltip as Tooltip in activeTooltips {
                if tooltip.presentingView == self {
                    return tooltip
                }
            }
        }

        return nil
    }
    
    /// Presents a tooltip to the calling view with a given view, orientation and configuration.
    ///
    /// - Parameter view: The view that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: The configuration allowing to customize the tooltip
    public func tooltip(_ view: UIView, orientation: Tooltip.Orientation, configuration: Tooltip.ToolTipConfiguration = Tooltip.ToolTipConfiguration()) {
        guard !hasActiveTooltip else { return }

        let tooltip = Tooltip(view: view, presentingView: self, orientation: orientation, configuration: configuration)
        
        add(tooltip: tooltip)
        anchor(tooltip: tooltip, orientation: orientation, configuration: configuration)
        tooltip.present()
    }
    
    /// Presents a tooltip to the calling view with a given text, orientation and configuration.
    ///
    /// - Parameter text    :The text that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: The configuration allowing to customize the tooltip
    public func tooltip(_ text: String, orientation: Tooltip.Orientation, configuration: Tooltip.ToolTipConfiguration = Tooltip.ToolTipConfiguration()) {
        guard !hasActiveTooltip else { return }
        let label = UILabel()
        label.textAlignment = configuration.labelConfiguration.textAlignment
        label.textColor = configuration.labelConfiguration.textColor
        label.font = configuration.labelConfiguration.font
        label.numberOfLines = 0
        label.text = text
        label.preferredMaxLayoutWidth = configuration.labelConfiguration.preferredMaxLayoutWidth
        
        let tooltip = Tooltip(view: label, presentingView: self, orientation: orientation, configuration: configuration)

        add(tooltip: tooltip)
        anchor(tooltip: tooltip, orientation: orientation, configuration: configuration)
        tooltip.present()
    }
    
    /// Presents a tooltip to the calling view with a given view, orientation and configuration closure.
    ///
    /// - Parameter view    :The view that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: A configuration closure allowing to customize the tooltip.
    public func tooltip(_ view: UIView, orientation: Tooltip.Orientation, configuration: ((Tooltip.ToolTipConfiguration) -> Tooltip.ToolTipConfiguration)) {
        tooltip(view, orientation: orientation, configuration: configuration(Tooltip.ToolTipConfiguration()))
    }
    
    /// Presents a tooltip to the calling view with a given text, orientation and configuration closure.
    ///
    /// - Parameter text    :The text that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: A configuration closure allowing to customize the tooltip.
    public func tooltip(_ text: String, orientation: Tooltip.Orientation, configuration: ((Tooltip.ToolTipConfiguration) -> Tooltip.ToolTipConfiguration)) {
        tooltip(text, orientation: orientation, configuration: configuration(Tooltip.ToolTipConfiguration()))
    }
}

extension UIBarItem {
    
    // Taken from https://github.com/teodorpatras/EasyTipView/blob/8a9133085074c41119516a22b4223f79b8698b40/Sources/EasyTipView/UIKitExtensions.swift#L15
    fileprivate var view: UIView? {
        if let item = self as? UIBarButtonItem, let customView = item.customView {
            return customView
        }
        return self.value(forKey: "view") as? UIView
    }
    
    /// Presents a tooltip to the calling view with a given view, orientation and configuration.
    ///
    /// - Parameter view    :The view that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: The configuration allowing to customize the tooltip
    public func tooltip(_ view: UIView, orientation: Tooltip.Orientation, configuration: Tooltip.ToolTipConfiguration = Tooltip.ToolTipConfiguration()) {
        guard let view = self.view else { return }
        view.tooltip(view, orientation: orientation, configuration: configuration)
    }
    
    /// Presents a tooltip to the calling view with a given view, orientation and configuration closure.
    ///
    /// - Parameter view    :The view that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: A configuration closure allowing to customize the tooltip.
    public func tooltip(_ view: UIView, orientation: Tooltip.Orientation, configuration: ((Tooltip.ToolTipConfiguration) -> Tooltip.ToolTipConfiguration)) {
        guard let view = self.view else { return }
        view.tooltip(view, orientation: orientation, configuration: configuration)
    }
    
    /// Presents a tooltip to the calling view with a given text, orientation and configuration.
    ///
    /// - Parameter text    :The text that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: The configuration allowing to customize the tooltip
    public func tooltip(_ text: String, orientation: Tooltip.Orientation, configuration: Tooltip.ToolTipConfiguration = Tooltip.ToolTipConfiguration()) {
        guard let view = self.view else { return }
        view.tooltip(text, orientation: orientation, configuration: configuration)
    }
    
    /// Presents a tooltip to the calling view with a given text, orientation and configuration closure.
    ///
    /// - Parameter text    :The text that will be displayed within the tooltip
    /// - Parameter orientation: The placement of the tooltip in relation to the presenting view
    /// - Parameter configuration: A configuration closure allowing to customize the tooltip.
    public func tooltip(_ text: String, orientation: Tooltip.Orientation, configuration: ((Tooltip.ToolTipConfiguration) -> Tooltip.ToolTipConfiguration)) {
        guard let view = self.view else { return }
        view.tooltip(text, orientation: orientation, configuration: configuration)
    }
}

extension Tooltip {
    /// Dismisses all tooltips that are currently shown on any sub view in the `window`.
    public static func dismissAll() {

        for window in UIApplication.shared.windows {
            let activeTooltips = window.subviews.filter({ $0 is Tooltip })

            activeTooltips.compactMap { $0 as? Tooltip }.forEach { $0.dismiss() }
        }
    }
}

#endif
