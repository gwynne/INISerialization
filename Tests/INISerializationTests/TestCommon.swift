import XCTest
@testable import INISerialization

/// Make SerializationErrors equatable for test comparisons
/// - WARNING: Keep in sync with the actual enum cases!!
extension INISerialization.SerializationError: Equatable {
    public static func ==(lhs: INISerialization.SerializationError, rhs: INISerialization.SerializationError) -> Bool {
        switch (lhs, rhs) {
            case (.encodingError, .encodingError):
                return true
            case (.unexpectedInput(let c1, let line1), .unexpectedInput(let c2, let line2)) where c1 == c2 && line1 == line2:
                return true
            case (.unterminatedString(let line1), .unterminatedString(let line2)) where line1 == line2:
                return true
            case (.commentInSectionHeader(let line1), .commentInSectionHeader(let line2)) where line1 == line2:
                return true
            case (.commentInterruptedKey(let line1), .commentInterruptedKey(let line2)) where line1 == line2:
                return true
            case (.tokenSequencingError(let line1), .tokenSequencingError(let line2)) where line1 == line2:
                return true
            case (.incompleteSectionHeader(let line1), .incompleteSectionHeader(let line2)) where line1 == line2:
                return true
            case (.incompleteKey(let line1), .incompleteKey(let line2)) where line1 == line2:
                return true
            case (.sectionsNotAllowed(let line1), .sectionsNotAllowed(let line2)) where line1 == line2:
                return true
            case (.tooManyBrackets(let line1), .tooManyBrackets(let line2)) where line1 == line2:
                return true
            case (.noKeyAvailable(let line1), .noKeyAvailable(let line2)) where line1 == line2:
                return true
            case (.missingSeparator(let line1), .missingSeparator(let line2)) where line1 == line2:
                return true
            case (.invalidSectionName(let line1), .invalidSectionName(let line2)) where line1 == line2:
                return true
            case (.invalidKeyName(let line1), .invalidKeyName(let line2)) where line1 == line2:
                return true
            case (.nestedTooDeep(let keyPath1), .nestedTooDeep(let keyPath2)) where keyPath1 == keyPath2:
                return true
            case (.invalidIdentifier(let keyPath1), .invalidIdentifier(let keyPath2)) where keyPath1 == keyPath2:
                return true
            case (.unsupportedType(let keyPath1, let type1), .unsupportedType(let keyPath2, let type2)) where keyPath1 == keyPath2 && type1 == type2:
                return true
            default:
                return false
        }
    }
}

/// "Pretty" printing for serialization read options
extension INISerialization.ReadingOptions: CustomDebugStringConvertible {
    public var debugDescription: String {
        return "[" + self.rawValue.setBits.map { [
            INISerialization.ReadingOptions.detectNumericValues.rawValue.trailingZeroBitCount: "numeric",
            INISerialization.ReadingOptions.detectSections.rawValue.trailingZeroBitCount: "sections",
            INISerialization.ReadingOptions.allowHashComments.rawValue.trailingZeroBitCount: "hash",
            INISerialization.ReadingOptions.allowTrailingComments.rawValue.trailingZeroBitCount: "trailing",
            INISerialization.ReadingOptions.uppercaseKeys.rawValue.trailingZeroBitCount: "upper",
            INISerialization.ReadingOptions.lowercaseKeys.rawValue.trailingZeroBitCount: "lower",
            INISerialization.ReadingOptions.detectBooleanValues.rawValue.trailingZeroBitCount: "boolean",
            INISerialization.ReadingOptions.allowMissingValues.rawValue.trailingZeroBitCount: "missing",
            INISerialization.ReadingOptions.allowSectionReset.rawValue.trailingZeroBitCount: "reset",
        ][$0]! }.joined(separator: ",") + "]"
    }
}

/// Convenience for creating parsed tokens at a given numeric location
extension ParsedToken {
    init(at offset: Int, line: UInt, _ data: Token) {
        self.init(position: .init(encodedOffset: offset), line: line, data: data)
    }
}

/// Sorta-functional-style-kinda access to individual bits of a `BinaryInteger`
/// Not very efficient, really
extension BinaryInteger {
    func hasBit(_ bit: Int) -> Bool {
        precondition(bit < self.bitWidth, "Requested bit must be within the bit width of this type")
        
        return (self & (1 << bit)) != 0
    }
    
    var eachBit: CountableRange<Int> { return (0..<self.bitWidth) }
    var setBits: [Int] { return self.eachBit.filter { self.hasBit($0) } }
}

/// Simple non-recursive power set algorithm for `OptionSet`s.
/// - Note: Can't put this on `SetAlgebra` because `SetAlgebra` is not
/// `RawRepresentable`, and therefore there's no generic way to iterate the
/// values in the set. Even with `OptionSet` we have to constrain the
/// conformance to `BinaryInteger` representations.
extension OptionSet where RawValue: BinaryInteger {
    func powerSet() -> [Self] {
        var result: [Self] = []
        
        self.rawValue.setBits.forEach { e in
            result.append(contentsOf: result.map { $0.union(Self.init(rawValue: RawValue(1 << e))) })
            result.append(Self.init(rawValue: RawValue(1 << e)))
        }
        return result
    }
}

/// "Pretty" printing for `ParsedToken` arrays
extension Array where Element == ParsedToken {
    public var tokenListDescription: String {
        var desc = ""

        for tok in self {
            desc += String(format: "\t@%2u:%3u - \n", tok.line, tok.position.encodedOffset) + tok.data.debugDescription + "\n"
        }
        return desc
    }
}

/// Re-"erase" the specific ordered/unordered type when using INIWriter because
/// it's more convenient for tests.
extension INIWriter {
    func serialize<T>(_ data: T) throws -> String where T: Sequence, T.Element == INIKeyValuePair {
        if let ordered = data as? INIOrderedObject {
            return try serialize(ordered)
        } else if let unordered = data as? INIUnorderedObject {
            return try serialize(unordered)
        } else {
            fatalError("You can't do that")
        }
    }
}
