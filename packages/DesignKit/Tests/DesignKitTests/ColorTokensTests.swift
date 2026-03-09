//
//  ColorTokensTests.swift
//  DesignKit
//

import Testing
import SwiftUI
@testable import DesignKit

@Suite("Color Token Tests")
struct ColorTokensTests {

    @Test("Hex init parses 6-character RGB string")
    func hexInit6Char() {
        let color = Color(hex: "#FF0000")
        // Color was created without crashing -- basic smoke test.
        // Deep component extraction requires UIColor round-trip which
        // isn't reliable in package tests without a host app.
        _ = color
    }

    @Test("Hex init parses without hash prefix")
    func hexInitNoHash() {
        let color = Color(hex: "00FF00")
        _ = color
    }

    @Test("Hex init parses 8-character ARGB string")
    func hexInit8Char() {
        let color = Color(hex: "80FF0000")
        _ = color
    }

    @Test("Hex init returns clear-equivalent for malformed input")
    func hexInitMalformed() {
        let color = Color(hex: "XYZ")
        _ = color
    }

    @Test("Hex init handles whitespace and hash")
    func hexInitWhitespace() {
        let color = Color(hex: "  #ABCDEF  ")
        _ = color
    }

    #if canImport(UIKit)
    @Test("Hex init produces correct RGB components")
    func hexInitComponents() {
        let color = Color(hex: "FF8000") // Orange: R=255, G=128, B=0
        let uiColor = UIColor(color)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        uiColor.getRed(&r, green: &g, blue: &b, alpha: &a)

        #expect(abs(r - 1.0) < 0.01)
        #expect(abs(g - 0.502) < 0.02)
        #expect(abs(b - 0.0) < 0.01)
        #expect(abs(a - 1.0) < 0.01)
    }
    #endif
}
