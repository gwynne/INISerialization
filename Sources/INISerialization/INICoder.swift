//
//  INICoder.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/10/17.
//

import Foundation

open class INIDecoder {
    
    /// If true, empty values will be omitted
    public var omitEmptyValues: Bool
    
    public init(omitEmptyValues: Bool = false) {
        self.omitEmptyValues = omitEmptyValues
    }
    
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    
    open func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let opts: INISerialization.ReadingOptions = [
            .allowHashComments,
            .allowMissingValues,
            .allowSectionReset,
            .allowTrailingComments,
            .detectBooleanValues,
            .detectNumericValues,
            .detectSections
        ]
        let topLevel = try INISerialization.iniObject(with: data, options: opts)
        let decoder = try _INIDecoder(referencing: topLevel, userInfo: self.userInfo, omitEmpty: omitEmptyValues)
        return try T(from: decoder)
    }
    
}

extension DecodingError {
    public static func typeMismatch(_ type: Any.Type, atPath path: [CodingKey], message: String? = nil) -> DecodingError {
        let pathString = path.map { $0.stringValue }.joined(separator: ".")
        let context = DecodingError.Context(
            codingPath: path,
            debugDescription: message ?? "No \(type) was found at path \(pathString)"
        )
        return Swift.DecodingError.typeMismatch(type, context)
    }
}

/// Decoder
fileprivate class _INIDecoder : Decoder {
    
    // - MARK: Guts
    
    fileprivate let omitEmpty: Bool
    fileprivate let container: Any
    
    fileprivate init(referencing: Any, codingPath: [CodingKey] = [], userInfo: [CodingUserInfoKey: Any], omitEmpty: Bool) throws {
        guard codingPath.count < 2 else {
            throw DecodingError.keyNotFound(
            	codingPath.last!,
                DecodingError.Context(codingPath: codingPath, debugDescription: "INI does not support nesting more than 1 level")
            )
        }
        self.container = referencing
        self.codingPath = codingPath
        self.userInfo = userInfo
        self.omitEmpty = omitEmpty
    }
    
    fileprivate func with<T>(pushedKey key: CodingKey, _ work: () throws -> T) rethrows -> T {
        self.codingPath.append(key)
        let ret: T = try work()
        self.codingPath.removeLast()
        return ret
    }

    fileprivate func unboxInt<T>(_ rawValue: Any, as type: T.Type) throws -> T where T: FixedWidthInteger {
        if let value = rawValue as? UInt {
            guard let result = T.init(exactly: value) else {
                throw DecodingError.typeMismatch(T.self, atPath: self.codingPath)
            }
            return result
        } else if let value = rawValue as? Int {
            guard let result = T.init(exactly: value) else {
                throw DecodingError.typeMismatch(T.self, atPath: self.codingPath)
            }
            return result
        } else {
            throw DecodingError.typeMismatch(T.self, atPath: self.codingPath)
        }
    }
    
    fileprivate func unboxFloat<T>(_ rawValue: Any, as type: T.Type) throws -> T where T: BinaryFloatingPoint {
        if let value = rawValue as? Double {
            return T.init(value)
        } else {
            throw DecodingError.typeMismatch(T.self, atPath: self.codingPath)
        }
    }
    
    // - MARK: Decoder protocol

    public var codingPath: [CodingKey]
    public var userInfo: [CodingUserInfoKey: Any]
    
    public func container<Key>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
        guard let data = container as? [String: Any] else {
            throw DecodingError.typeMismatch([String: Any].self, atPath: self.codingPath)
        }
        return KeyedDecodingContainer(_INIKeyedDecodingContainer<Key>(referencing: self, wrapping: data))
    }
    
    public func unkeyedContainer() throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, atPath: self.codingPath, message: "Arrays are not supported by INI")
    }
    
    public func singleValueContainer() throws -> SingleValueDecodingContainer {
        return _INISingleValueDecodingContainer(referencing: self, wrapping: container)
    }
}

/// Keyed container
fileprivate struct _INIKeyedDecodingContainer<K: CodingKey> : KeyedDecodingContainerProtocol {
    typealias Key = K
    
    // - MARK: Guts
    
    private let decoder: _INIDecoder
    private let container: [String: Any]
    
    fileprivate init(referencing: _INIDecoder, wrapping: [String: Any]) {
        self.decoder = referencing
        self.container = wrapping
        self.codingPath = decoder.codingPath
    }

    private func requireKey(_ key: K) throws -> Any {
        guard let entry = self.container[key.stringValue] else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "No value associated with key \(key) (\"\(key.stringValue)\").")
            )
        }
        return entry
    }
    
    private func requireType<T>(_ type: T.Type, forKey key: K) throws -> T {
        return try self.decoder.with(pushedKey: key) {
            guard let value = try requireKey(key) as? T else {
                throw DecodingError.valueNotFound(
                    type,
                    DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found something else.")
                )
            }
            return value
        }
    }

    private func unbox<T>(_ type: T.Type, forKey key: K) throws -> T where T: FixedWidthInteger {
        return try self.decoder.with(pushedKey: key) { try self.decoder.unboxInt(self.requireKey(key), as: type) }
    }
    private func unbox<T>(_ type: T.Type, forKey key: K) throws -> T where T: BinaryFloatingPoint {
        return try self.decoder.with(pushedKey: key) { try self.decoder.unboxFloat(self.requireKey(key), as: type) }
    }

    // - MARK: KeyedDecodingContainerProtocol
    
    public var codingPath: [CodingKey]
    public var allKeys: [Key] { return self.container.keys.flatMap { Key(stringValue: $0) } }
    public func contains(_ key: Key) -> Bool { return self.container[key.stringValue] != nil }
    
    public func decodeNil(forKey key: K) throws -> Bool {
        return try self.decoder.with(pushedKey: key) {
            let rawValue = try requireKey(key)
            
            if let value = rawValue as? String, value == "", self.decoder.omitEmpty {
                return true
            }
            return false
        }
    }
    
    public func decode(_ type: Bool.Type, forKey key: K) throws -> Bool     { return try requireType(type, forKey: key) }
    public func decode(_ type: Int.Type, forKey key: K) throws -> Int       { return try unbox(type, forKey: key) }
    public func decode(_ type: Int8.Type, forKey key: K) throws -> Int8     { return try unbox(type, forKey: key) }
    public func decode(_ type: Int16.Type, forKey key: K) throws -> Int16   { return try unbox(type, forKey: key) }
    public func decode(_ type: Int32.Type, forKey key: K) throws -> Int32   { return try unbox(type, forKey: key) }
    public func decode(_ type: Int64.Type, forKey key: K) throws -> Int64   { return try unbox(type, forKey: key) }
    public func decode(_ type: UInt.Type, forKey key: K) throws -> UInt     { return try unbox(type, forKey: key) }
    public func decode(_ type: UInt8.Type, forKey key: K) throws -> UInt8   { return try unbox(type, forKey: key) }
    public func decode(_ type: UInt16.Type, forKey key: K) throws -> UInt16 { return try unbox(type, forKey: key) }
    public func decode(_ type: UInt32.Type, forKey key: K) throws -> UInt32 { return try unbox(type, forKey: key) }
    public func decode(_ type: UInt64.Type, forKey key: K) throws -> UInt64 { return try unbox(type, forKey: key) }
    public func decode(_ type: Float.Type, forKey key: K) throws -> Float   { return try unbox(type, forKey: key) }
    public func decode(_ type: Double.Type, forKey key: K) throws -> Double { return try unbox(type, forKey: key) }
    public func decode(_ type: String.Type, forKey key: K) throws -> String { return try requireType(type, forKey: key) }
    public func decode<T>(_ type: T.Type, forKey key: K) throws -> T where T : Decodable {
        return try self.decoder.with(pushedKey: key) {
            let value = try requireKey(key)
            
        	return try T(from: _INIDecoder(
                referencing: value,
                codingPath: self.decoder.codingPath,
                userInfo: self.decoder.userInfo,
                omitEmpty: self.decoder.omitEmpty
            ))
        }
    }
    
    public func nestedContainer<NestedKey>(keyedBy type: NestedKey.Type, forKey key: K) throws -> KeyedDecodingContainer<NestedKey> where NestedKey : CodingKey {
    	let value = try requireType([String: Any].self, forKey: key)
        
        return KeyedDecodingContainer(_INIKeyedDecodingContainer<NestedKey>(referencing: self.decoder, wrapping: value))
    }
    
    public func nestedUnkeyedContainer(forKey key: K) throws -> UnkeyedDecodingContainer {
        throw DecodingError.typeMismatch([Any].self, atPath: self.codingPath, message: "Arrays are not supported by INI")
    }
    
    public func superDecoder() throws -> Decoder {
        return try _INIDecoder(
            referencing: container,
            codingPath: self.decoder.codingPath,
            userInfo: self.decoder.userInfo,
            omitEmpty: self.decoder.omitEmpty
        )
    }
    
    public func superDecoder(forKey key: K) throws -> Decoder {
        return try self.decoder.with(pushedKey: key) { try superDecoder() }
    }
}

/// Single value container
fileprivate struct _INISingleValueDecodingContainer: SingleValueDecodingContainer {
    
    // - MARK: Guts
    
    private let decoder: _INIDecoder
    private let container: Any
    
    fileprivate init(referencing: _INIDecoder, wrapping: Any) {
        self.decoder = referencing
        self.container = wrapping
        self.codingPath = decoder.codingPath
    }

    private func requireType<T>(_ type: T.Type) throws -> T {
        guard let value = container as? T else {
            throw DecodingError.valueNotFound(
                type,
                DecodingError.Context(codingPath: self.decoder.codingPath, debugDescription: "Expected \(type) value but found something else.")
            )
        }
        return value
    }
    
    // - MARK: SingleValueDecodingContainer protocol
    
    public var codingPath: [CodingKey]
    
    public func decodeNil() -> Bool {
        if let value = container as? String, value == "", self.decoder.omitEmpty {
            return true
        }
        return false
    }
    public func decode(_ type: Bool.Type) throws -> Bool     { return try requireType(type) }
    public func decode(_ type: Int.Type) throws -> Int       { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: Int8.Type) throws -> Int8     { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: Int16.Type) throws -> Int16   { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: Int32.Type) throws -> Int32   { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: Int64.Type) throws -> Int64   { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: UInt.Type) throws -> UInt     { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: UInt8.Type) throws -> UInt8   { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: UInt16.Type) throws -> UInt16 { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: UInt32.Type) throws -> UInt32 { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: UInt64.Type) throws -> UInt64 { return try self.decoder.unboxInt(container, as: type) }
    public func decode(_ type: Float.Type) throws -> Float   { return try self.decoder.unboxFloat(container, as: type) }
    public func decode(_ type: Double.Type) throws -> Double { return try self.decoder.unboxFloat(container, as: type) }
    public func decode(_ type: String.Type) throws -> String { return try requireType(type) }
    public func decode<T>(_ type: T.Type) throws -> T where T : Decodable {
        return try T(from: _INIDecoder(
            referencing: container,
            codingPath: self.decoder.codingPath,
            userInfo: self.decoder.userInfo,
            omitEmpty: self.decoder.omitEmpty
        ))
    }
}
