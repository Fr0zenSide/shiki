//
//  DateFormatter+Extensions.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 04/04/2024.
//

import Foundation

public extension DateFormatter {
    /// Date formatter configured for PocketBase's UTC-based ISO 8601 format
    /// with fractional seconds and a space between date and time.
    ///
    /// Example: `2024-04-04 13:47:54.692Z`
    static var pocketbase: ISO8601DateFormatter {
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        dateFormatter.formatOptions = [.withInternetDateTime,
                                       .withFractionalSeconds,
                                       .withSpaceBetweenDateAndTime]
        return dateFormatter
    }
}

public extension JSONDecoder {
    func pocketbaseDateDecodingStrategy() -> (_ decoder: any Decoder) throws -> Date {
        { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            if let date = DateFormatter.pocketbase.date(from: dateString) {
                return date
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode date string \(dateString)")
            }
        }
    }
}
