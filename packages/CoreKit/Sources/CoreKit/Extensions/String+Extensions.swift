//
//  String+Extensions.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 17/04/2024.
//

import Foundation

public extension String {
    func trim() -> String {
        self.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removeOccurences(of characterSet: CharacterSet) -> String {
        self.replacingOccurences(from: characterSet, with: "")
    }

    func removes(of substring: String) -> String {
        self.replacingOccurrences(of: substring, with: "", options: [.caseInsensitive, .regularExpression])
    }

    func replacingOccurences(from characterSet: CharacterSet, with string: String) -> String {
        self.components(separatedBy: characterSet).joined(separator: string)
    }

    func isValid(for characterSet: CharacterSet) -> Bool {
        let invalidCharacters = self.replacingOccurences(from: characterSet.inverted, with: "")
        return invalidCharacters.isEmpty
    }
}
