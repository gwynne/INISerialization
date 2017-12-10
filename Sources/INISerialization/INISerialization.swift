//
//  INISerialization.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/02/17.
//

import Foundation

open class INISerialization {
    
    public struct ReadingOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        
        /// If set, detect numeric values that will fit in an Int64 (or UInt64)
        /// and provide the value as an integer type instead of a String. An
        /// attempt is also made to detect floating-point values which will fit
        /// in a `Float` or `Double`. If unset, numeric values will be returned
        /// as Strings. If `detectQuotedValues` is also set, quoting a value
        /// will disable numeric detection.
        public static let detectNumericValues = ReadingOptions(rawValue: 1 << 0)
        
        /// If set, detect INI section headers of the form `[HEADER]` and return
        /// second-level dictionary values. "key path" section headers are _not_
        /// supported; only one level of nesting is allowed. If not set, section
        /// headers are treated as a syntax error.
        public static let detectSections = ReadingOptions(rawValue: 1 << 1)
        
        /// If set, allow `#` as a comment character in addition to `;`.
        public static let allowHashComments = ReadingOptions(rawValue: 1 << 2)
        
        /// If set, allow comments to appear after values as well as on their
        /// own lines.
        public static let allowTrailingComments = ReadingOptions(rawValue: 1 << 3)
        
        /// If set, all keys are uppercased in the returned dictionary. Section
        /// header names **are** affected by this setting. If `lowercaseKeys` is
        /// also set, lowercase always wins.
        public static let uppercaseKeys = ReadingOptions(rawValue: 1 << 4)

        /// If set, all keys are lowercased in the returned dictionary. Section
        /// header names **are** affected by this setting. If `uppercaseKeys` is
        /// also set, lowercase always wins.
        public static let lowercaseKeys = ReadingOptions(rawValue: 1 << 5)
        
        /// If set, boolean values are detected. The recognized boolean values
        /// are "false", "true", "yes", "no", "on", and "off", all case-
        /// insensitive.
        public static let detectBooleanValues = ReadingOptions(rawValue: 1 << 6)
        
        /// If set, a key with no `=` and no trailing non-whitespace text on the
        /// same line is treated as having an empty value. If unset, a key with
        /// no `=` is a hard syntax error.
        ///
        /// ````
        /// KEY=      ; key with empty value
        /// KEY       ; if allowMissingValues, same as above
        /// KEY foo   ; always a syntax error
        /// ````
        public static let allowMissingValues = ReadingOptions(rawValue: 1 << 7)
        
        /// If set, a section header with no name (e.g. `[]`) will "reset" the
        /// current section to "none", putting keys back at the top level. If
        /// unset, a section header with no name is a syntax error. Ignored if
        /// `.detectSections` is not also set.
        public static let allowSectionReset = ReadingOptions(rawValue: 1 << 8)
    }
    
    public struct WritingOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
    }
    
    public enum SerializationError: Error {
        /// The data could not be interpreted according to the given encoding
        case encodingError
        /// Unexpected character found in input
        case unexpectedInput(Character, line: UInt)
        /// Unterminated quoted string in quoted-detect mode
        case unterminatedString(line: UInt)
        /// Comment appeared while reading section header
        case commentInSectionHeader(line: UInt)
        /// Comment appeared while looking for an = separator and missing values
        /// or trailing comments are not allowed
        case commentInterruptedKey(line: UInt)
        /// A tokenization error occurred (a non-newline token was found while
        /// waiting for end of line, or found ourselves in an impossible state)
        case tokenSequencingError(line: UInt)
        /// A section header was started but not finished when a newline was
        /// ecnountered.
        case incompleteSectionHeader(line: UInt)
        /// A key was declared but no separator was found before end of line,
        /// and missing values are not enabled.
        case incompleteKey(line: UInt)
        /// A section header opener was encountered, but sections are not
        /// enabled.
        case sectionsNotAllowed(line: UInt)
        /// An extraneous section header opener or closer was encountered.
        case tooManyBrackets(line: UInt)
        /// An extraneous key/value separator was found floating about.
        case noKeyAvailable(line: UInt)
        /// A value (such as quoted string) was found with no viable key.
        case missingSeparator(line: UInt)
        /// A section header contained invalid characters
        case invalidSectionName(line: UInt)
        /// A key name contained invalid characters
        case invalidKeyName(line: UInt)
    }
    
    // Partially cribbed from JSONSerialization
    // NSString.stringEncoding(for: Data, ...) doesn't seem to be available on Linux
    private class func _detectUnicodeEncoding(_ bytes: UnsafePointer<UInt8>, length: Int) -> (String.Encoding, skipLength: Int) {
        if length >= 2 {
            switch (bytes[0], bytes[1]) {
                case (0xEF, 0xBB):
                    if length >= 3 && bytes[2] == 0xBF {
                        return (.utf8, 3)
                    }
                case (0x00, 0x00):
                    if length >= 4 && bytes[2] == 0xFE && bytes[3] == 0xFF {
                        return (.utf32BigEndian, 4)
                    }
                case (0xFF, 0xFE):
                    if length >= 4 && bytes[2] == 0x00 && bytes[3] == 0x00 {
                        return (.utf32LittleEndian, 4)
                    }
                    return (.utf16LittleEndian, 2)
                case (0xFE, 0xFF):
                    return (.utf16BigEndian, 2)
                default:
                    break
            }
        }
        if length >= 4 {
            switch (bytes[0], bytes[1], bytes[2], bytes[3]) {
                case (0, 0, 0, _):
                    return (.utf32BigEndian, 0)
                case (_, 0, 0, 0):
                    return (.utf32LittleEndian, 0)
                case (0, _, 0, _):
                    return (.utf16BigEndian, 0)
                case (_, 0, _, 0):
                    return (.utf16LittleEndian, 0)
                default:
                    break
            }
        } else if length >= 2 {
            switch (bytes[0], bytes[1]) {
                case (0, _):
                    return (.utf16BigEndian, 0)
                case (_, 0):
                    return (.utf16LittleEndian, 0)
                default:
                    break
            }
        }
        return (.utf8, 0)
    }
    
    open class func iniObject(with data: Data, encoding enc: String.Encoding? = nil, options opt: ReadingOptions = []) throws -> [String: Any] {
        return try data.withUnsafeBytes { (bytes: UnsafePointer<UInt8>) -> [String: Any] in
            let encoding = enc != nil ? (enc!, skipLength: 0) : _detectUnicodeEncoding(bytes, length: data.count)
            let buffer = UnsafeBufferPointer<UInt8>(start: bytes.advanced(by: encoding.skipLength), count: data.count - encoding.skipLength)
            
            // Potentially inefficient and memory-heavy, but for now the easiest
            // way to support arbitrary encodings (which are more likely to be
            // found in an INI file than in, say, JSON).
            guard let rawText = String(bytes: buffer, encoding: encoding.0) else {
                throw SerializationError.encodingError
            }
            
            return try INIParser.parse(rawText, options: opt)
        }
    }
    
    class func data(withIniObject obj: [String: Any?], options opt: WritingOptions = []) throws -> Data {
        fatalError("Serializing data to INI format is not implemented.")
    }
    
}

