//
//  INIWriter.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/10/17.
//

import Foundation

internal class INIWriter {
    
    init() {}
    
    private func serializeKey(_ key: String, under topKey: String?) throws -> String {
        if let _ = key.rangeOfCharacter(from: INITokenizer.notIdentifier) {
            throw INISerialization.SerializationError.invalidIdentifier(keyPath: [topKey, key].flatMap { $0 }.joined(separator: "."))
        }
        return key
    }
    
    private func serializeUInt<T: UnsignedInteger>(_ value: T) throws -> String {
        return String(UInt(value))
    }
    
    private func serializeInt<T: SignedInteger>(_ value: T) throws -> String {
        return String(Int(value))
    }
    
    private func serializeFloat<T: BinaryFloatingPoint>(_ value: T) throws -> String {
        // There is no Double.init(BinaryFloatingPoint), so we resort to type disambiguation for now
        if let f = value as? Float {
            return String(f)
        } else if let d = value as? Double {
            return String(d)
        } else {
            fatalError("Someone didn't update serializeFloat() when they updated serializeValue()'s type checks") // eww
        }
    }
    
    private func serializeString(_ value: String) throws -> String {
        switch value.rangeOfCharacter(from: INITokenizer.notIdentifier) {
            case .none:
                return value
            case .some:
                // If there are non-identifier characters in the value, quote
                // it, including adding necessary escapes.
                return "\"" + value.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
    }
    
    private func serializeBool(_ value: Bool) throws -> String {
        return value ? "true" : "false"
    }

    private func serializeValue(_ value: Any, forKey key: String, under topKey: String? = nil) throws -> String {
        let keyPart = try serializeKey(key, under: topKey)
        let valuePart: String
        
        if let _ = value as? INIUnorderedObject {
            throw INISerialization.SerializationError.nestedTooDeep(keyPath: [topKey, key].flatMap { $0 }.joined(separator: "."))
        } else if let _ = value as? INIOrderedObject {
            throw INISerialization.SerializationError.nestedTooDeep(keyPath: [topKey, key].flatMap { $0 }.joined(separator: "."))
        }
        else if let uintValue = value as? UInt { valuePart = try serializeUInt(uintValue) }
        else if let uintValue = value as? UInt8 { valuePart = try serializeUInt(uintValue) }
        else if let uintValue = value as? UInt16 { valuePart = try serializeUInt(uintValue) }
        else if let uintValue = value as? UInt32 { valuePart = try serializeUInt(uintValue) }
        else if let uintValue = value as? UInt64 { valuePart = try serializeUInt(uintValue) }
        else if let intValue = value as? Int { valuePart = try serializeInt(intValue) }
        else if let intValue = value as? Int8 { valuePart = try serializeInt(intValue) }
        else if let intValue = value as? Int16 { valuePart = try serializeInt(intValue) }
        else if let intValue = value as? Int32 { valuePart = try serializeInt(intValue) }
        else if let intValue = value as? Int64 { valuePart = try serializeInt(intValue) }
        else if let floatValue = value as? Float { valuePart = try serializeFloat(floatValue) }
        else if let floatValue = value as? Double { valuePart = try serializeFloat(floatValue) }
        else if let stringValue = value as? String { valuePart = try serializeString(stringValue) }
        else if let boolValue = value as? Bool { valuePart = try serializeBool(boolValue) }
        else {
            throw INISerialization.SerializationError.unsupportedType(keyPath: [topKey, key].flatMap { $0 }.joined(separator: "."), type: type(of: value))
        }
        return keyPart + " " + "=" + " " + valuePart
    }
    
    /// Serialize a non-root object (e.g. a section)
    private func serializeSection<T>(_ object: T, forKey topKey: String) throws -> String where T: Sequence, T.Element == INIKeyValuePair {
        let serializedKeys = try object.map { try serializeValue($0.value, forKey: $0.key, under: topKey) }

        return
            "[" + topKey + "]" + "\n" +
            serializedKeys.joined(separator: "\n")
    }
    
    /// Serialize a root object. This is not exposed even internally because it
    /// would permit serialization of arbitrary sequence types, and that is not
    /// supported. The only reason this generic routine exists is to perform
    /// type erasure for INIUnorderedObject and INIOrderedObject.
    private func serializeRoot<T>(_ object: T) throws -> String where T: Sequence, T.Element == INIKeyValuePair {
        var serializedKeys: [String] = []
        var serializedSections: [String] = []
        
        for (key, value) in object {
            if let obj = value as? INIUnorderedObject {
                serializedSections.append(try serializeSection(obj, forKey: key))
            } else if let obj = value as? INIOrderedObject {
                serializedSections.append(try serializeSection(obj, forKey: key))
            } else {
                serializedKeys.append(try serializeValue(value, forKey: key))
            }
        }
        
        return serializedKeys.joined(separator: "\n") + (serializedKeys.isEmpty ? "" : "\n") +
               serializedSections.joined(separator: "\n") + (serializedSections.isEmpty ? "" : "\n")
    }
    
    /// Serialize an unordered set of key-value pairs, potentially nesting one
    /// level deep. Top-level keys will always appear before sections in the
    /// output, but no other ordering of is guaranteed. Keys in sections will
    /// either be sorted or not depending on whether the nested object is
    /// ordered or unordered.
    func serialize(_ object: INIUnorderedObject) throws -> String {
        return try serializeRoot(object)
    }
    
    /// Serialize an ordered set of key-value pairs, potentially nesting one
    /// level deep. Top-level keys will always appear before sections in the
    /// output, in the order in which they appear in the array. Keys in sections
    /// will either be sorted or not depending on whether the nested object is
    /// ordered or unordered.
    func serialize(_ object: INIOrderedObject) throws -> String {
        return try serializeRoot(object)
    }
}
