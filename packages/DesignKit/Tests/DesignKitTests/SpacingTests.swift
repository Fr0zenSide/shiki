//
//  SpacingTests.swift
//  DesignKit
//

import Testing
import SwiftUI
@testable import DesignKit

@Suite("Spacing Tests")
struct SpacingTests {

    @Test("SpacingScale raw values follow geometric progression")
    func spacingScaleValues() {
        #expect(SpacingScale.xs.rawValue == 4)
        #expect(SpacingScale.sm.rawValue == 8)
        #expect(SpacingScale.md.rawValue == 16)
        #expect(SpacingScale.lg.rawValue == 32)
        #expect(SpacingScale.xl.rawValue == 64)
        #expect(SpacingScale.xxl.rawValue == 96)
    }

    @Test("CornerRadiusScale raw values are correct")
    func cornerRadiusValues() {
        #expect(CornerRadiusScale.small.rawValue == 4)
        #expect(CornerRadiusScale.medium.rawValue == 6)
        #expect(CornerRadiusScale.card.rawValue == 12)
        #expect(CornerRadiusScale.badge.rawValue == 20)
    }

    @Test("SpacingScale CaseIterable returns all cases")
    func spacingAllCases() {
        #expect(SpacingScale.allCases.count == 6)
    }

    @Test("CornerRadiusScale CaseIterable returns all cases")
    func cornerRadiusAllCases() {
        #expect(CornerRadiusScale.allCases.count == 4)
    }

    @Test("DefaultSpacing provides correct default values")
    func defaultSpacingValues() {
        let spacing = DefaultSpacing()
        #expect(spacing.xs == SpacingScale.xs.rawValue)
        #expect(spacing.sm == SpacingScale.sm.rawValue)
        #expect(spacing.md == SpacingScale.md.rawValue)
        #expect(spacing.lg == SpacingScale.lg.rawValue)
        #expect(spacing.xl == SpacingScale.xl.rawValue)
        #expect(spacing.xxl == SpacingScale.xxl.rawValue)
        #expect(spacing.cornerSmall == CornerRadiusScale.small.rawValue)
        #expect(spacing.cornerMedium == CornerRadiusScale.medium.rawValue)
        #expect(spacing.cornerCard == CornerRadiusScale.card.rawValue)
        #expect(spacing.cornerBadge == CornerRadiusScale.badge.rawValue)
    }

    @Test("Custom spacing overrides work")
    func customSpacing() {
        let spacing = DefaultSpacing(xs: 2, sm: 4, md: 8)
        #expect(spacing.xs == 2)
        #expect(spacing.sm == 4)
        #expect(spacing.md == 8)
        // Non-overridden values keep defaults
        #expect(spacing.lg == 32)
    }

    @Test("TypeScale default sizes are correct")
    func typeScaleDefaults() {
        #expect(TypeScale.display.defaultSize == 34)
        #expect(TypeScale.title.defaultSize == 28)
        #expect(TypeScale.title3.defaultSize == 20)
        #expect(TypeScale.body.defaultSize == 17)
        #expect(TypeScale.caption.defaultSize == 13)
        #expect(TypeScale.label.defaultSize == 11)
    }

    @Test("TypeScale label is uppercased")
    func typeScaleUppercase() {
        #expect(TypeScale.label.isUppercased == true)
        #expect(TypeScale.body.isUppercased == false)
        #expect(TypeScale.display.isUppercased == false)
    }

    @Test("SystemTypographyProvider returns fonts for all scales")
    func systemTypographyProvider() {
        let provider = SystemTypographyProvider()
        for scale in TypeScale.allCases {
            _ = provider.font(for: scale)
        }
    }
}
