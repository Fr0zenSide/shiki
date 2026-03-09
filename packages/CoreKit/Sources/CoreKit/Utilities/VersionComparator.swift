//
//  VersionComparator.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 26/02/2026.
//

import Foundation

public enum VersionComparator: Sendable {
    /// Compare two semantic version strings (e.g. "1.2.3" vs "1.3.0").
    /// Splits by ".", compares each component numerically.
    /// Missing components are treated as 0 (e.g. "1.2" == "1.2.0").
    public static func compare(_ v1: String, _ v2: String) -> ComparisonResult {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }
        let maxLen = max(parts1.count, parts2.count)

        for i in 0..<maxLen {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return .orderedAscending }
            if p1 > p2 { return .orderedDescending }
        }
        return .orderedSame
    }
}
