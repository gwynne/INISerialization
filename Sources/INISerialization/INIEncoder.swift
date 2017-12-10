//
//  INIEncoder.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/10/17.
//

import Foundation

open class INIEncoder {
    
    open var userInfo: [CodingUserInfoKey: Any] = [:]
    
    public init() {}
    
    open func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = _INIEncoder(userInfo: userInfo)
        
        try value.encode(to: encoder)
        return try INISerialization.data(withIniObject: encoder.result.data, encoding: .utf8, options: [])
    }

}

fileprivate class _INIEncoder : Encoder {
    // - MARK: Guts
    
    var result: _INIPartiallyEncodedData
    
    init(userInfo: [CodingUserInfoKey: Any], codingPath: [CodingKey] = [], referencing: _INIPartiallyEncodedData = .init(data: INIOrderedObject())) {
        self.userInfo = userInfo
        self.codingPath = codingPath
        self.result = referencing
    }
    
    fileprivate func with<T>(pushedKey key: CodingKey, _ work: () throws -> T) rethrows -> T {
        self.codingPath.append(key)
        let ret = try work()
        self.codingPath.removeLast()
        return ret
    }
    
    // - MARK: Encoder protocol
    
    public var codingPath: [CodingKey]
    public var userInfo: [CodingUserInfoKey : Any]
    
    public func container<Key: CodingKey>(keyedBy type: Key.Type) -> KeyedEncodingContainer<Key> {
        return .init(_INIKeyedEncodingContainer<Key>(referencing: self, codingPath: self.codingPath, wrapping: result))
    }
    
    public func unkeyedContainer() -> UnkeyedEncodingContainer {
        // can't throw from Encoder.unkeyedContainer() - why?
        fatalError("INI encoder doesn't support arrays")
    }
    
    public func singleValueContainer() -> SingleValueEncodingContainer {
        return _INISingleValueEncodingContainer(referencing: self, codingPath: self.codingPath, wrapping: result)
    }
}

fileprivate final class _INIPartiallyEncodedData {
    fileprivate var data: INIOrderedObject
    
    fileprivate init(data: INIOrderedObject) {
        self.data = data
    }
    
    private func findKey(_ key: CodingKey) -> (idx: INIOrderedObject.Index, key: String, value: INIOrderedObject)? {
        guard let idx = data.index(where: { $0.key == key.stringValue && $0.value is INIOrderedObject }) else {
            return nil
        }
        
        return (idx, data[idx].key, data[idx].value as! INIOrderedObject)
    }
    
    fileprivate func set(_ value: Any, atPath path: [CodingKey]) throws {
        switch path.count {
            case 1:
                self.data.append((key: path[0].stringValue, value))
            case 2:
                if let info = findKey(path[0]) {
                    var obj = info.value
                    obj.append((path[1].stringValue, value))
                    data[info.idx] = (info.key, obj)
                } else {
                    data.append((path[0].stringValue, INIOrderedObject([INIKeyValuePair(path[1].stringValue, value)])))
                }
            default:
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: path, debugDescription: "Can't nest \(path.count) levels deep in INI encoder"))
        }
    }
}

fileprivate class _INIKeyedEncodingContainer<K: CodingKey>: KeyedEncodingContainerProtocol {
    typealias Key = K
    
    // - MARK: Guts
    
    private let encoder: _INIEncoder
    private let container: _INIPartiallyEncodedData
    
    init(referencing: _INIEncoder, codingPath: [CodingKey], wrapping: _INIPartiallyEncodedData) {
        self.encoder = referencing
        self.codingPath = codingPath
        self.container = wrapping
    }
    
    // - MARK: KeyedEncodingContainerProtocol protocol
    
    public var codingPath: [CodingKey]
    
    public func encodeNil(forKey key: K) throws {
    	try self.encoder.with(pushedKey: key) { try container.set("", atPath: self.encoder.codingPath) }
    }
    
    public func encode(_ value: Bool, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Int, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Int8, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Int16, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Int32, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Int64, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: UInt, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: UInt8, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: UInt16, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: UInt32, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: UInt64, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Float, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: Double, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode(_ value: String, forKey key: K) throws { try encoder.with(pushedKey: key) { try container.set(value, atPath: encoder.codingPath) } }
    public func encode<T>(_ value: T, forKey key: K) throws where T : Encodable {
        try encoder.with(pushedKey: key) {
            let innerEncoder = _INIEncoder(userInfo: encoder.userInfo, codingPath: encoder.codingPath, referencing: encoder.result)
            
            try value.encode(to: innerEncoder)
        }
    }
    public func nestedContainer<NestedKey: CodingKey>(keyedBy keyType: NestedKey.Type, forKey key: K) -> KeyedEncodingContainer<NestedKey> {
        return encoder.with(pushedKey: key) {
            .init(_INIKeyedEncodingContainer<NestedKey>(referencing: encoder, codingPath: encoder.codingPath, wrapping: container))
        }
    }
    
    public func nestedUnkeyedContainer(forKey key: K) -> UnkeyedEncodingContainer {
        // can't throw from KeyedEncodingContainerProtocol.nestedUnkeyedContainer() - why?
        fatalError("INI encoder doesn't support arrays")
    }
    
    public func superEncoder() -> Encoder {
        return _INIEncoder(userInfo: encoder.userInfo, codingPath: encoder.codingPath, referencing: encoder.result)
    }
    
    public func superEncoder(forKey key: K) -> Encoder {
        return encoder.with(pushedKey: key) { superEncoder() }
    }
}

fileprivate class _INISingleValueEncodingContainer: SingleValueEncodingContainer {
    
    // - MARK: Guts
    
    private let encoder: _INIEncoder
    private let container: _INIPartiallyEncodedData
    
    fileprivate init(referencing: _INIEncoder, codingPath: [CodingKey], wrapping: _INIPartiallyEncodedData) {
        self.encoder = referencing
        self.codingPath = codingPath
        self.container = wrapping
    }
    
    // - MARK: SingleValueEncodingContainer protocol
    
    public var codingPath: [CodingKey]
    
    public func encodeNil() throws { try container.set("", atPath: self.codingPath) }
    public func encode(_ value: Bool) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Int) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Int8) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Int16) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Int32) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Int64) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: UInt) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: UInt8) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: UInt16) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: UInt32) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: UInt64) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Float) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: Double) throws { try container.set(value, atPath: self.codingPath) }
    public func encode(_ value: String) throws { try container.set(value, atPath: self.codingPath) }
    public func encode<T>(_ value: T) throws where T : Encodable {
        let innerEncoder = _INIEncoder(userInfo: encoder.userInfo, codingPath: self.codingPath, referencing: self.container)
        
        try value.encode(to: innerEncoder)
    }
}
