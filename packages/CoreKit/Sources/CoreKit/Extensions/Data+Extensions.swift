//
//  Data+Extensions.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 04/04/2024.
//

import Foundation

public extension Data {
    var prettyJson: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self, options: []),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted]),
              let prettyPrintedString = String(data: data, encoding: .utf8) else { return nil }
        return prettyPrintedString
    }
}
