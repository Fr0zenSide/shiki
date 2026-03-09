//
//  Dictionary+Extensions.swift
//  CoreKit
//
//  Extracted from WabiSabi — Created by Jeoffrey Thirot on 14/03/2023.
//

import Foundation

public extension Dictionary where Key: ExpressibleByStringLiteral, Value: AnyObject {
    func toJSON(_ options: JSONSerialization.WritingOptions = [.prettyPrinted]) throws -> Data {
        try JSONSerialization.data(withJSONObject: self, options: options)
    }

    func toJson(_ options: JSONSerialization.WritingOptions = [.prettyPrinted]) -> Data? {
        try? toJSON(options)
    }

    func decode<DecodableType: Decodable>() throws -> DecodableType {
        let data = try self.toJSON()
        let decoder = JSONDecoder()
        return try decoder.decode(DecodableType.self, from: data)
    }
}

public extension Dictionary where Key: ExpressibleByStringLiteral, Value: Any {
    func toJSON(_ options: JSONSerialization.WritingOptions = [.prettyPrinted]) throws -> Data {
        try JSONSerialization.data(withJSONObject: self, options: options)
    }

    func toJson(_ options: JSONSerialization.WritingOptions = [.prettyPrinted]) -> Data? {
        try? toJSON(options)
    }

    func decode<DecodableType: Decodable>() throws -> DecodableType {
        let data = try self.toJSON()
        let decoder = JSONDecoder()
        return try decoder.decode(DecodableType.self, from: data)
    }
}
