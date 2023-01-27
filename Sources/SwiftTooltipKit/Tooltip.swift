//
//  Tooltip.swift
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

#if canImport(UIKit)
import Foundation
import UIKit

open class Tooltip: UIView {

    private static let TooltipLayerIdentifier: String = "toolTipID"
    static let margin: CGFloat = 16.0

    public enum Orientation {
        case top, bottom, left, right, leading, trailing
    }
    
    private enum AdjustmentType {
        case left, right, top, bottom
    }

    /// content of the tool tip, e.g. a label or image
    public private(set) var contentView: UIView!

    /// the view that owns the tooltip
    public private(set) weak var presentingView: UIView!
    
    public private(set) var configuration: ToolTipConfiguration!

    /// The initial orientation for the tooltip
    public private(set) var orientation: Orientation = .top
    /// The initial frame for the tooltip before any adjustments are applied
    private var initialFrame = CGRect.zero
    
    private var presentingViewFrame: CGRect {
        guard let presentingView = presentingView else { return .zero }
        return presentingView.convert(presentingView.bounds, to: window)
    }
    
    private var adjustmentTypes: Set<AdjustmentType> = []

    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: The x value of the origin

    private func originXValue(orientation: Orientation) -> CGFloat {
        switch orientation {
        case .top, .bottom:
            return presentingViewFrame.midX
        case .right:
            return presentingViewFrame.maxX + configuration.offset
        case .left:
            return presentingViewFrame.minX - configuration.offset
        case .leading:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                return presentingViewFrame.maxX + configuration.offset
            case .leftToRight:
                fallthrough
            @unknown default:
                return presentingViewFrame.minX - configuration.offset
            }
        case .trailing:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                return presentingViewFrame.minX - configuration.offset
            case .leftToRight:
                fallthrough
            @unknown default:
                return presentingViewFrame.maxX + configuration.offset
            }
        }
    }

    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Return: the y value of the origin

    private func originYValue(orientation: Orientation) -> CGFloat {
        switch orientation {
        case .top:
            return presentingViewFrame.minY - configuration.offset
        case .bottom:
            return presentingViewFrame.maxY + configuration.offset
        case .left, .right, .leading, .trailing:
            return presentingViewFrame.midY
        }
    }
    
    private var remainingOrientations: [Orientation] = [.top, .bottom, .right, .left, .leading, .trailing]
    
    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: The next orientation
    ///
    private func nextOrientation(orientation: Orientation) -> Orientation {

        var rndElement: Orientation {
            remainingOrientations.randomElement() ?? .top
        }
        
        switch orientation {
        case .top:
            remainingOrientations = remainingOrientations.remove(.top)
            return remainingOrientations.contains(.bottom) ? .bottom : rndElement
        case .bottom:
            remainingOrientations = remainingOrientations.remove(.bottom)
            return remainingOrientations.contains(.top) ? .top : rndElement
        case .left:
            remainingOrientations = remainingOrientations.remove(.left)
            return remainingOrientations.contains(.right) ? .right : rndElement
        case .right:
            remainingOrientations = remainingOrientations.remove(.right)
            return remainingOrientations.contains(.left) ? .left : rndElement
        case .leading:
            remainingOrientations = remainingOrientations.remove(.leading)
            return remainingOrientations.contains(.trailing) ? .trailing : rndElement
        case .trailing:
            remainingOrientations = remainingOrientations.remove(.trailing)
            return remainingOrientations.contains(.leading) ? .leading : rndElement
        }
    }

    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: A boolean, true if the orientation is verticle
    private func hasVerticalOrientation(orientation: Orientation) -> Bool {
        return orientation == .top || orientation == .bottom
    }

    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: A boolean, true if the orientation is horizontal

    private func hasHorizontalOrientation(orientation: Orientation) -> Bool {
        return orientation == .left || orientation == .right || orientation == .leading || orientation == .trailing
    }
    
    public convenience init(view: UIView, presentingView: UIView, orientation: Orientation, configuration: ((ToolTipConfiguration) -> ToolTipConfiguration)) {
        self.init(view: view, presentingView: presentingView, orientation: orientation)
        self.configuration = configuration(ToolTipConfiguration())
        
        setup()
    }
    
    public convenience init(view: UIView, presentingView: UIView, orientation: Orientation, configuration: ToolTipConfiguration = ToolTipConfiguration()) {
        self.init(view: view, presentingView: presentingView, orientation: orientation)
        self.configuration = configuration
        
        setup()
    }
    
    fileprivate init(view: UIView, presentingView: UIView, orientation: Orientation) {
        self.orientation = orientation
        self.contentView = view
        self.presentingView = presentingView
        
        super.init(frame: .zero)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented. Use convenience initializers instead.")
    }
    
    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        
        contentView.translatesAutoresizingMaskIntoConstraints = false
        self.addSubview(contentView)
        NSLayoutConstraint.activate([
            contentView.topAnchor.constraint(equalTo: self.topAnchor),
            contentView.leadingAnchor.constraint(equalTo: self.leadingAnchor),
            contentView.trailingAnchor.constraint(equalTo: self.trailingAnchor),
            contentView.bottomAnchor.constraint(equalTo: self.bottomAnchor)
        ])
        
        backgroundColor = configuration.backgroundColor
        
        // animate showing
        alpha = 0.0
        
        // If configured, handles automatic dismissal
        handleAutomaticDismissalIfNeeded()
    }
    
    /// If the custom view contains a label that has no `preferredMaxLayoutWidth` set, it can happen that its width > screen size width.
    /// To prevent that artificially adjust the `preferredMaxLayoutWidth` to stay within bounds.
    private func adjustPreferredMaxLayoutWidthIfPossible() {

        let labels = contentView.subviews
            .compactMap { $0 as? UILabel }

        let filterLabels = labels.filter { $0.preferredMaxLayoutWidth == 0.0 ||
            $0.preferredMaxLayoutWidth > UIScreen.main.bounds.width - Tooltip.margin*2.0 ||
            $0.intrinsicContentSize.width > UIScreen.main.bounds.width - Tooltip.margin*2.0 }

        filterLabels.forEach {
            if $0.preferredMaxLayoutWidth != UIScreen.main.bounds.width - Tooltip.margin*2.0 {
                $0.preferredMaxLayoutWidth = UIScreen.main.bounds.width - Tooltip.margin*2.0
                contentView.setNeedsLayout()
            }
        }
    
        contentView.layoutIfNeeded()
    }
    
    /// Computes the original frame of the tooltip.
    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: A tuple of the adjusted rect and the adjusted orientation

    private func computeFrame(orientation: Orientation) -> (rect: CGRect, orientation: Orientation) {

        adjustPreferredMaxLayoutWidthIfPossible()
        
        let viewSize = contentView.boundsOrIntrinsicContentSize
        
        let origin: CGPoint
        switch orientation {
        case .top:
            // take tipsize into account
            origin = CGPoint(x: originXValue(orientation: orientation) - viewSize.width/2.0, y: originYValue(orientation: orientation) - viewSize.height)
        case .bottom:
            origin = CGPoint(x: originXValue(orientation: orientation) - viewSize.width/2.0, y: originYValue(orientation: orientation))
        case .left:
            origin = CGPoint(x: originXValue(orientation: orientation) - viewSize.width, y: originYValue(orientation: orientation) - viewSize.height/2.0)
        case .right:
            origin = CGPoint(x: originXValue(orientation: orientation), y: originYValue(orientation: orientation) - viewSize.height/2.0)
        case .leading:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                origin = CGPoint(x: originXValue(orientation: orientation), y: originYValue(orientation: orientation) - viewSize.height/2.0)
            case .leftToRight:
                fallthrough
            @unknown default:
                origin = CGPoint(x: originXValue(orientation: orientation) - viewSize.width, y: originYValue(orientation: orientation) - viewSize.height/2.0)
            }
        case .trailing:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                origin = CGPoint(x: originXValue(orientation: orientation) - viewSize.width, y: originYValue(orientation: orientation) - viewSize.height/2.0)
            case .leftToRight:
                fallthrough
            @unknown default:
                origin = CGPoint(x: originXValue(orientation: orientation), y: originYValue(orientation: orientation) - viewSize.height/2.0)
            }
        }

        let rect = CGRect(x: origin.x, y: origin.y, width: viewSize.width, height: viewSize.height)

        // The initialFrame is the frame before any offsets are applied, since it should never change, we set it just once.
        if initialFrame == .zero {
            initialFrame = rect
        }
        
        let result = validateRect(rect, adjustedX: origin.x, adjustedY: origin.y, orientation: orientation)

        if result.orientation != orientation {
            return computeFrame(orientation: result.orientation)
        }

        return result
    }
    
    /// Validates the tooltip frame and updates frame and/or orientation if it's necessary.
    /// - Parameter rect: the rect that needs validation
    /// - Parameter adjustedX: the x coordinate of the rect's origin
    /// - Parameter adjustedY: the y coordinate of the rect's origin
    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: A tuple of the adjusted rect and the adjusted orientation
    private func validateRect(_ rect: CGRect, adjustedX: CGFloat, adjustedY: CGFloat, orientation: Orientation) -> (rect: CGRect, orientation: Orientation) {

        var orientation = orientation
        let screenBounds = UIScreen.main.bounds
        let globalSafeAreasInsets = safeAreaInsets

        precondition(rect.width <= screenBounds.width - Tooltip.margin*2.0, warningMsg())
        precondition(rect.height <= screenBounds.height - Tooltip.margin*2.0 - globalSafeAreasInsets.top - globalSafeAreasInsets.bottom, warningMsg())
        
        switch orientation {
        case .top:
            if contentView.boundsOrIntrinsicContentSize.height + Tooltip.margin + globalSafeAreasInsets.top > presentingViewFrame.minY {
                orientation = nextOrientation(for: orientation)
            }
        case .bottom:
            if screenBounds.height - contentView.boundsOrIntrinsicContentSize.height - Tooltip.margin - globalSafeAreasInsets.bottom < presentingViewFrame.maxY {
                orientation = nextOrientation(for: orientation)
            }
            
        case .left:
            if contentView.boundsOrIntrinsicContentSize.width + Tooltip.margin + globalSafeAreasInsets.left > presentingViewFrame.minX {
                orientation = nextOrientation(for: orientation)
            }
        case .right:
            if screenBounds.width - contentView.boundsOrIntrinsicContentSize.width - Tooltip.margin - globalSafeAreasInsets.bottom <  presentingViewFrame.maxX {
                orientation = nextOrientation(for: orientation)
            }
        case .leading:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                if screenBounds.width - contentView.boundsOrIntrinsicContentSize.width - Tooltip.margin - globalSafeAreasInsets.bottom <  presentingViewFrame.maxX {
                    orientation = nextOrientation(for: orientation)
                }
            case .leftToRight:
                fallthrough
            @unknown default:
                if contentView.boundsOrIntrinsicContentSize.width + Tooltip.margin + globalSafeAreasInsets.left > presentingViewFrame.minX {
                    orientation = nextOrientation(for: orientation)
                }
            }

        case .trailing:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                    if contentView.boundsOrIntrinsicContentSize.width + Tooltip.margin + globalSafeAreasInsets.left > presentingViewFrame.minX {
                        orientation = nextOrientation(for: orientation)
                    }
            case .leftToRight:
                fallthrough
            @unknown default:
                if screenBounds.width - contentView.boundsOrIntrinsicContentSize.width - Tooltip.margin - globalSafeAreasInsets.bottom <  presentingViewFrame.maxX {
                    orientation = nextOrientation(for: orientation)
                }
            }
        }
        
        if adjustedY < Tooltip.margin + globalSafeAreasInsets.top {
            adjustmentTypes.insert(.top)
            return validateRect(
                rect,
                adjustedX: adjustedX,
                adjustedY: Tooltip.margin + globalSafeAreasInsets.top,
                orientation: orientation
            )
        } else if adjustedY > screenBounds.height - Tooltip.margin - globalSafeAreasInsets.bottom {
            adjustmentTypes.insert(.bottom)
            return validateRect(
                rect,
                adjustedX: adjustedX,
                adjustedY: screenBounds.height - Tooltip.margin - globalSafeAreasInsets.bottom,
                orientation: orientation
            )
        } else if adjustedX < Tooltip.margin {
            adjustmentTypes.insert(.left)
            return validateRect(
                rect,
                adjustedX: Tooltip.margin,
                adjustedY: adjustedY,
                orientation: orientation
            )
        } else if adjustedX > screenBounds.width - Tooltip.margin - contentView.boundsOrIntrinsicContentSize.width {
            adjustmentTypes.insert(.right)
            return validateRect(
                rect,
                adjustedX: screenBounds.width - Tooltip.margin - contentView.boundsOrIntrinsicContentSize.width,
                adjustedY: adjustedY,
                orientation: orientation
            )
        }
        return (CGRect(origin: CGPoint(x: adjustedX, y: adjustedY), size: rect.size), orientation)
    }
    
    private var orientationsTried: Set<Orientation> = []

    /// - Parameter prevOrientation: The current orientation of the tooltip.
    /// - Returns: The new adjusted orientation

    private func nextOrientation(for prevOrientation: Orientation) -> Orientation {
        switch prevOrientation {
        case .top:
            orientationsTried.insert(.top)
            if !orientationsTried.contains(.bottom) { return .bottom }
            return .left
        case .bottom:
            orientationsTried.insert(.bottom)
            if !orientationsTried.contains(.top) { return .top }
            return .left
        case .left:
            orientationsTried.insert(.left)
            if !orientationsTried.contains(.right) { return .right }
            return .top
        case .right:
            orientationsTried.insert(.right)
            if !orientationsTried.contains(.left) { return .left }
            return .top
        case .leading:
            orientationsTried.insert(.leading)
            if !orientationsTried.contains(.trailing) { return .trailing }
            return .top
        case .trailing:
            orientationsTried.insert(.trailing)
            if !orientationsTried.contains(.leading) { return .leading }
            return .top
        }
    }
    
    private func handleAutomaticDismissalIfNeeded() {
        guard configuration.dismissAutomatically else { return }
        Timer.scheduledTimer(withTimeInterval: configuration.timeToDismiss, repeats: false, block: { [weak self] _ in
            self?.dismiss()
        })
    }
    
    open override func layoutSubviews() {
        super.layoutSubviews()
        
        contentView.layoutIfNeeded()
        
        let result = computeFrame(orientation: orientation)
        self.frame = result.rect
        drawToolTip(orientation: result.orientation)
    }
    
    /// Draws the rect of the tooltip
    /// - Parameter orientation: The current orientation of the tooltip.

    private func drawToolTip(orientation: Orientation) {
        // remove previously added layers to prevent double drawing
        self.layer.sublayers?.removeAll(where: { $0.name == Tooltip.TooltipLayerIdentifier })
        let bounds = self.bounds
        let inset = configuration.inset
        let roundRect = CGRect(x: bounds.minX - inset, y: bounds.minY - inset, width: bounds.width + inset * 2.0, height: bounds.height + inset * 2.0)
        let roundRectBez = UIBezierPath(roundedRect: roundRect, cornerRadius: 5.0)
        
        if configuration.showTip {
            let trianglePath = drawTip(bounds: bounds, orientation: orientation)
            roundRectBez.append(trianglePath)
        }
        roundRectBez.lineWidth = 2.0
        
        let shape = createShapeLayer(roundRectBez.cgPath)
        self.layer.insertSublayer(shape, at: 0)
    }
    
    /// Draws the tip of the tooltip fitting the specified orientation
    /// - Parameter bounds: The bounds of the tooltip
    /// - Parameter orientation: The current orientation of the tooltip.
    /// - Returns: The bezier path of the tip
    private func drawTip(bounds: CGRect, orientation: Orientation) -> UIBezierPath {
        let tipPath = UIBezierPath()
        let tipSize = configuration.tipSize
        let inset = configuration.inset

        var xValueCenter: CGFloat = bounds.midX
        var yValueCenter: CGFloat = bounds.midY
        
        switch orientation {
        case .top, .bottom:
            xValueCenter = bounds.midX
        case .left, .right, .leading, .trailing:
            xValueCenter = bounds.minY
        }
        
        for adjustmentType in adjustmentTypes {
            if (adjustmentType == .right || adjustmentType == .left) && hasVerticalOrientation(orientation: orientation) {
                xValueCenter = bounds.midX + initialFrame.minX - frame.minX // The change from the initialFrame
            }
            
            if (adjustmentType == .top || adjustmentType == .bottom) && hasHorizontalOrientation(orientation: orientation) {
                yValueCenter = bounds.midY + initialFrame.minY - frame.minY // The change from the initialFrame
            }
        }
        
        switch orientation {
        case .top:
                tipPath.move(to: CGPoint(x: xValueCenter - tipSize.width/2.0, y: bounds.maxY + inset ))
            tipPath.addLine(to: CGPoint(x: xValueCenter + tipSize.width/2.0, y: bounds.maxY + inset ))
            tipPath.addLine(to: CGPoint(x: xValueCenter, y: bounds.maxY + tipSize.height ))
            tipPath.addLine(to: CGPoint(x: xValueCenter - tipSize.width/2.0, y: bounds.maxY + inset ))
        case .bottom:
            tipPath.move(to: CGPoint(x: xValueCenter - tipSize.width/2.0, y: bounds.minY - inset))
            tipPath.addLine(to: CGPoint(x: xValueCenter + tipSize.width/2.0, y: bounds.minY - inset))
            tipPath.addLine(to: CGPoint(x: xValueCenter, y: bounds.minY - tipSize.height ))
            tipPath.addLine(to: CGPoint(x: xValueCenter - tipSize.width/2.0, y: bounds.minY - inset))
        case .left:
            tipPath.move(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
            tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter + tipSize.height/2.0 ))
            tipPath.addLine(to: CGPoint(x: bounds.maxX + tipSize.height, y: yValueCenter ))
            tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
        case .right:
            tipPath.move(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
            tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter + tipSize.height/2.0 ))
            tipPath.addLine(to: CGPoint(x: bounds.minX - tipSize.height, y: yValueCenter ))
            tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
        case .leading:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                tipPath.move(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter + tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - tipSize.height, y: yValueCenter ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
            case .leftToRight:
                fallthrough
            @unknown default:
                tipPath.move(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter + tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + tipSize.height, y: yValueCenter ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
            }
        case .trailing:
            switch effectiveUserInterfaceLayoutDirection {
            case .rightToLeft:
                tipPath.move(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter + tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + tipSize.height, y: yValueCenter ))
                tipPath.addLine(to: CGPoint(x: bounds.maxX + inset, y: yValueCenter - tipSize.height/2.0 ))
            case .leftToRight:
                fallthrough
            @unknown default:
                tipPath.move(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter + tipSize.height/2.0 ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - tipSize.height, y: yValueCenter ))
                tipPath.addLine(to: CGPoint(x: bounds.minX - inset, y: yValueCenter - tipSize.height/2.0 ))
            }
        }
        
        tipPath.close()
        return tipPath
    }
    
    func createShapeLayer(_ path : CGPath) -> CAShapeLayer {
        let shape = CAShapeLayer()
        shape.path = path
        shape.fillColor = configuration.backgroundColor.cgColor
        shape.shadowColor = configuration.shadowConfiguration.shadowColor
        shape.shadowOffset = configuration.shadowConfiguration.shadowOffset
        shape.shadowRadius = configuration.cornerRadius
        shape.shadowOpacity = configuration.shadowConfiguration.shadowOpacity
        shape.name = Tooltip.TooltipLayerIdentifier
        return shape
    }
    
    /// Dismisses the tooltip.
    open func dismiss() {
        UIView.animate(
            withDuration: configuration.animationConfiguration.animationDuration,
            delay: configuration.animationConfiguration.animationDelay,
            options: configuration.animationConfiguration.animationOptions,
            animations: { [weak self] in
                self?.alpha = 0.0
                self?.configuration.onDismiss?()
            },
            completion: { [weak self] _ in
                self?.isHidden = true
                self?.removeFromSuperview()
            }
        )
    }
    
    /// Presents the tooltip.
    open func present() {
        UIView.animate(
            withDuration: configuration.animationConfiguration.animationDuration,
            delay: configuration.animationConfiguration.animationDelay,
            options: configuration.animationConfiguration.animationOptions,
            animations: { [unowned self] in
                self.configuration.onPresent?()
                self.alpha = 1.0
            }
        )
    }
    
    private func warningMsg() -> String {
        """
            LAYOUT WARNING:
        
            It seems that the view displayed as a tooltip is too large!
            Please make sure that size of the tooltip is valid and try again.
        """
        
    }
    
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if !self.bounds.contains(point) {
            dismiss()
            return false
        }
        return true
    }
}

#endif
