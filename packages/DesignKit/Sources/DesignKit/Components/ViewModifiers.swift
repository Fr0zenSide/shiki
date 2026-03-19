//
//  ViewModifiers.swift
//  DesignKit
//
//  Generic reusable view modifiers extracted from WabiSabi.
//

import SwiftUI

// MARK: - Hidden Modifier

/// Conditionally hides a view based on a binding.
public struct HiddenModifier: ViewModifier {

    @Binding public var isHidden: Bool

    public init(isHidden: Binding<Bool>) {
        self._isHidden = isHidden
    }

    public func body(content: Content) -> some View {
        if isHidden {
            content.hidden()
        } else {
            content
        }
    }
}

extension View {

    /// Conditionally hides the view based on a binding.
    /// - Parameter isHidden: Binding that controls visibility.
    /// - Returns: A view that is hidden or visible.
    public func hidden(_ isHidden: Binding<Bool>) -> some View {
        modifier(HiddenModifier(isHidden: isHidden))
    }
}

// MARK: - Bar Progress Style

/// A horizontal bar progress view style with customizable height and color.
public struct BarProgressStyle: ProgressViewStyle {

    public var height: Double
    public var color: AnyShapeStyle
    public var labelFontStyle: Font

    public init(
        height: Double = 20.0,
        color: any ShapeStyle = Color.accentColor.gradient,
        labelFontStyle: Font = .body
    ) {
        self.height = height
        self.color = AnyShapeStyle(color)
        self.labelFontStyle = labelFontStyle
    }

    public func makeBody(configuration: Configuration) -> some View {
        let progress = configuration.fractionCompleted ?? 0.0

        GeometryReader { geometry in
            VStack(alignment: .leading) {
                configuration.label
                    .font(labelFontStyle)

                RoundedRectangle(cornerRadius: 10.0)
                    .fill(Color.gray.opacity(0.2))
                    .frame(height: height)
                    .frame(width: geometry.size.width)
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 10.0)
                            .fill(color)
                            .frame(width: geometry.size.width * progress)
                            .overlay {
                                if let currentValueLabel = configuration.currentValueLabel {
                                    currentValueLabel
                                        .font(.headline)
                                        .foregroundColor(.white)
                                }
                            }
                    }
            }
        }
    }
}

extension ProgressViewStyle where Self == BarProgressStyle {

    /// Bar progress style with customizable height and color.
    public static func bar(
        height: Double = 20.0,
        color: any ShapeStyle = Color.accentColor.gradient
    ) -> Self {
        .init(height: height, color: color)
    }
}

// MARK: - Draggable Modifier

/// Adds a drag-to-dismiss gesture with rotation and snap-back animation.
public struct DraggableModifier: ViewModifier {

    @State private var offset = CGSize.zero

    public init() {}

    public func body(content: Content) -> some View {
        content
            .shadow(color: .gray.opacity(0.3), radius: 10, x: 8, y: 15)
            .rotationEffect(.degrees(Double(offset.height / 20)))
            .offset(x: 0, y: offset.height)
            .gesture(
                DragGesture()
                    .onChanged { gesture in
                        offset = gesture.translation
                    }
                    .onEnded { _ in
                        withAnimation(.easeIn(duration: 0.3)) {
                            offset = .zero
                        }
                    }
            )
    }
}

extension View {

    /// Adds a draggable gesture with rotation and snap-back.
    public func closeDraggable() -> some View {
        modifier(DraggableModifier())
    }
}

// MARK: - Scaled Button Style

/// A generic button style with press animation (scale + opacity).
///
/// Provides a customizable full-width button with rounded corners.
public struct ScaledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    public let textColor: Color
    public let backgroundStyle: AnyShapeStyle
    public let borderColor: Color
    public let borderWidth: CGFloat
    public let cornerRadius: CGFloat
    public let height: CGFloat

    public init(
        textColor: Color = .white,
        backgroundStyle: any ShapeStyle = Color.accentColor.gradient,
        borderColor: Color = .clear,
        borderWidth: CGFloat = 1,
        cornerRadius: CGFloat = 12,
        height: CGFloat = 74
    ) {
        self.textColor = textColor
        self.backgroundStyle = AnyShapeStyle(backgroundStyle)
        self.borderColor = borderColor
        self.borderWidth = borderWidth
        self.cornerRadius = cornerRadius
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .font(.title)
            .background(backgroundStyle)
            .foregroundStyle(textColor)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(alignment: .center) {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(borderColor, lineWidth: borderWidth)
            }
            .contentShape(Rectangle())
            .opacity(isEnabled ? 1.0 : 0.7)
            .opacity(configuration.isPressed ? 0.5 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.94 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ScaledButtonStyle {

    /// Primary full-width button with accent gradient.
    public static var scaled: Self { .init() }

    /// Outlined secondary button with no fill.
    public static var scaledSecondary: Self {
        .init(
            textColor: DefaultColors.defaultTextPrimary.opacity(0.8),
            backgroundStyle: Color.clear,
            borderColor: DefaultColors.defaultTextPrimary.opacity(0.6)
        )
    }
}
