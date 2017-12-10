//
//  INITokenizer.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/3/17.
//

import Foundation

// This extension allows us to directly question whether a given Character (e.g.
// a full-blown grapheme cluster) is a member of a CharacterSet. This isn't
// really correct for surrogate pairs especially, since CharacterSet only deals
// in UnicodeScalars (e.g. individual code points), but it's close enough.
//
// There has to be a more efficient way to do this - is this fast if it's
// "known" that there's only one scalar in a given grapheme cluster?
extension CharacterSet {
    func contains(_ member: Character) -> Bool {
        for s in member.unicodeScalars {
            if !contains(s) {
                return false
            }
        }
        return true
    }
}

/// A raw INI token
internal enum Token: Equatable {
    case commentMarker(String) // ; or #
    case newline // \r, \n, \r\n
    case sectionOpen // [
    case sectionClose // ]
    case separator // =
    case quotedString(String, doubleQuoted: Bool) // ' and "
    case integer(Substring)
    case decimal(Substring)
    case bareFalse(Substring) // "0", "false", or "no"
    case bareTrue(Substring) // "1", "true", or "yes"
    case whitespace(Substring)
    case identifier(Substring) // [a-zA-Z0-9_-]+
    case text(Substring) // non-whitespace
    
    static func ==(lhs: Token, rhs: Token) -> Bool {
        switch (lhs, rhs) {
            case (.newline, .newline):                                return true
            case (.sectionOpen, .sectionOpen):                        return true
            case (.sectionClose, .sectionClose):                    return true
            case (.separator, .separator):                            return true
            case (.commentMarker(let l), .commentMarker(let r)):    return l == r
            case (.integer(let l), .integer(let r)):                return l == r
            case (.decimal(let l), .decimal(let r)):                return l == r
            case (.bareFalse(let l), .bareFalse(let r)):            return l == r
            case (.bareTrue(let l), .bareTrue(let r)):                return l == r
            case (.whitespace(let l), .whitespace(let r)):          return l == r
            case (.identifier(let l), .identifier(let r)):          return l == r
            case (.text(let l), .text(let r)):                        return l == r
            case (.quotedString(let l, let ld), .quotedString(let r, let rd)):
                return l == r && ld == rd
            default:                                                return false
        }
    }
}

/// A raw INI token and information on where in the data it was found
internal struct ParsedToken: Equatable {
    let position: String.Index
    let line: UInt
    let data: Token
    
    static func ==(lhs: ParsedToken, rhs: ParsedToken) -> Bool {
        return lhs.position == rhs.position && lhs.line == rhs.line && lhs.data == rhs.data
    }
}

/// Tokenizer
internal struct INITokenizer {
    // - MARK: "External" interface
    
    init(_ text: NSString) {
        self.text = text
        self.loc = (text as String).startIndex
        self.line = 1
    }
    
    mutating func nextToken() throws -> ParsedToken? {
        return try parseToken()
    }
    
    static func tokenize(_ text: String) throws -> [ParsedToken] {
        var tokens: [ParsedToken] = []
        var tokenizer = INITokenizer(text as NSString)
        
        while let token = try tokenizer.nextToken() {
            tokens.append(token)
        }
        return tokens
    }
    
    static func tokenize(_ text: String, work: (INITokenizer, ParsedToken) throws -> Void) throws {
        var tokenizer = INITokenizer(text as NSString)

        while let token = try tokenizer.nextToken() {
            try work(tokenizer, token)
        }
    }
    
    // - MARK: Guts
    
    static private let whitespace = CharacterSet.whitespaces, notWhitespace = whitespace.inverted
    static private let newline = CharacterSet.newlines
    static private let decimal = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")), notDecimal = decimal.inverted
    static private let identifier = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-")), notIdentifier = identifier.inverted
    static private let doubleQuoteStops = CharacterSet(charactersIn: "\"\\").union(CharacterSet.newlines)
    static private let singleQuoteStops = CharacterSet(charactersIn: "'\\").union(CharacterSet.newlines)
    static private let significant = CharacterSet.whitespacesAndNewlines.union(CharacterSet(charactersIn: "[]="))

    /// TODO: Is the NSString shenanigan to avoid copying really needed?
    var text: NSString
    var loc: String.Index
    var line: UInt
    
    /// Are we currently at the string EOF?
    func eof() -> Bool { return loc >= end() }
    
    /// Convenience to get String.endIndex on NSString
    func end() -> String.Index { return (text as String).endIndex }
    
    /// String.index(_, offsetBy:, limitedBy:) that returns the limit instead of
    /// nil if it's reached.
    func minIdx(for adv: String.IndexDistance) -> String.Index {
        return (text as String).index(loc, offsetBy: adv, limitedBy: end()) ?? end()
    }
    
    /// Find the next character in string which is in the given `CharacterSet`,
    /// optionally skipping past that character while returning it and always
    /// returning the text which was skipped over.
    func nextOf(_ set: CharacterSet, skipping: Bool) -> (loc: String.Index, char: Character?, skipped: Substring) {
        let place = (text as String).rangeOfCharacter(from: set, options: [], range: loc..<end())
        
        if let p = place {
            return (
                loc: skipping ? (text as String).index(after: p.lowerBound) : p.lowerBound,
                char: (text as String)[p.lowerBound],
                skipped: (text as String)[loc..<p.lowerBound]
            )
        } else {
            return (loc: end(), char: nil, skipped: (text as String)[loc..<end()])
        }
    }
    
    /// Just an equality comparison which takes a range to search
    func matchAgainst(_ str: String, options cmpOpts: String.CompareOptions = []) -> Bool {
        return (text as String).compare(str, options: cmpOpts, range: loc..<minIdx(for: str.count), locale: nil) == .orderedSame
    }
    
    /// Sneak peek at what the next character is
    func peekChar() -> Character {
        return (text as String)[loc]
    }
    
    /// Get the next character and advance past it
    mutating func nextChar() -> Character {
        let c = (text as String)[loc]
        loc = (text as String).index(after: loc)
        return c
    }
    
    /// Read a single or double quoted string, interpreting \ escapes as needed
    mutating func nextQuotedString() throws -> Token {
        let type = nextChar()
        
        assert(type == "\"" || type == "'", "Quoted string got called when it wasn't one")
        
        var tok = ""
        
        while !eof() {
            let nextStop = nextOf(type == "\"" ? INITokenizer.doubleQuoteStops : INITokenizer.singleQuoteStops, skipping: true)
            
            switch nextStop.char {
                case .none:
                    throw INISerialization.SerializationError.unterminatedString(line: line)
                case .some(let char) where char == type:
                    loc = nextStop.loc
                    return .quotedString(tok + nextStop.skipped, doubleQuoted: type == "\"")
                case .some(let char) where char == "\\":
                    loc = nextStop.loc
                    tok += nextStop.skipped
                    if eof() {
                        throw INISerialization.SerializationError.unterminatedString(line: line)
                    }
                    let nextc = nextChar()
                    switch nextc {
                        case "\\": tok += "\\"
                        case type: tok.append(type)
                        case _ where INITokenizer.newline.contains(nextc): throw INISerialization.SerializationError.unterminatedString(line: line)
                        default: tok.append("\\"); tok.append(nextc)
                    }
                case .some: // only newlines left in the set, we'll just assume this
                    throw INISerialization.SerializationError.unterminatedString(line: line)
            }
        }
        // Is it actually possible to get here?
        throw INISerialization.SerializationError.unterminatedString(line: line) // EOF
    }
    
    /// Read a newline, treating a \r\n sequence as a single newline
    mutating func nextNewline() -> Token {
        assert(INITokenizer.newline.contains(peekChar()), "Newline get called when it wasn't one")

        let nl = nextChar()
        
        if nl == "\r" && peekChar() == "\n" {
            _ = nextChar() // Skip \r\n-style newline
        }
        return .newline
    }
    
    /// Read some whitespace
    mutating func nextWhitespace() -> Token {
        assert(INITokenizer.whitespace.contains(peekChar()), "Whitespace got called when it wasn't")
        
        let nextStop = nextOf(INITokenizer.notWhitespace, skipping: false)
        
        assert(nextStop.skipped.count > 0, "Can't skip zero if next character was in the set")
        loc = nextStop.loc
        return .whitespace(nextStop.skipped)
    }
    
    /// Read text data, interpreting boolean and numeric values if those were
    /// respectively requested, and deciding whether the text qualifies as an
    /// identifier.
    mutating func nextText() -> Token {
        assert(INITokenizer.significant.inverted.contains(peekChar()), "Text got called but something more significant is available")
        
        let nextStop = nextOf(INITokenizer.significant, skipping: false)
        
        assert(nextStop.skipped.count > 0, "Can't skip zero if next character was in the set")
        loc = nextStop.loc
        
        // Treat boolean names specially
        if nextStop.skipped.compare("true", options: .caseInsensitive, range: nil, locale: nil) == .orderedSame ||
           nextStop.skipped.compare("yes", options: .caseInsensitive, range: nil, locale: nil) == .orderedSame
        {
            return .bareTrue(nextStop.skipped)
        }
        if nextStop.skipped.compare("false", options: .caseInsensitive, range: nil, locale: nil) == .orderedSame ||
           nextStop.skipped.compare("no", options: .caseInsensitive, range: nil, locale: nil) == .orderedSame
        {
            return .bareFalse(nextStop.skipped)
        }
        // Interpret integer and floating-point values
        if let _ = Int(nextStop.skipped) {
            return .integer(nextStop.skipped)
        }
        if let _ = Double(nextStop.skipped) {
            return .decimal(nextStop.skipped)
        }
        // If there aren't any non-identifier characters, it's an identifier
        if nextStop.skipped.rangeOfCharacter(from: INITokenizer.notIdentifier) == nil {
            return .identifier(nextStop.skipped)
        }
        // Otherwise it's text
        return .text(nextStop.skipped)
    }
    
    /// Parse the next token, returning nil on EOF
    mutating func parseToken() throws -> ParsedToken? {
        // Quit if we hit the end
        guard !eof() else { return nil }
        
        // Save the token start and check out the next character
        let tokStart = loc, c = peekChar()
        
        switch c {
            // Comment
            case ";", "#":
                return ParsedToken(position: tokStart, line: line, data: .commentMarker(String(nextChar())))
//                let eol = nextOf(INITokenizer.newline, skipping: false)
//
//                loc = eol.loc
//                line += 1 // Even if we're at EOF, bump the line number anyway because consistency
//                if !eof() { // comment could appear at EOF, in which case there's no newline to skip
//                    _ = nextNewline() // comment implliclty includes newline
//                }
//                return ParsedToken(position: tokStart, line: line - 1, data: .comment(eol.skipped))
            // Section name opener
            case "[":
                _ = nextChar()
                return ParsedToken(position: tokStart, line: line, data: .sectionOpen)
            // Section name closer
            case "]":
                _ = nextChar()
                return ParsedToken(position: tokStart, line: line, data: .sectionClose)
            // Key/value separator
            case "=":
                _ = nextChar()
                return ParsedToken(position: tokStart, line: line, data: .separator)
            // Quoted string
            case "\"", "'":
                return ParsedToken(position: tokStart, line: line, data: try nextQuotedString())
            // Whitespace
            case _ where INITokenizer.whitespace.contains(c):
                return ParsedToken(position: tokStart, line: line, data: nextWhitespace())
            // Newline
            case _ where INITokenizer.newline.contains(c):
                line += 1 // Do this here so returned values are accurate
                return ParsedToken(position: tokStart, line: line - 1, data: nextNewline())
            // Boolean, number, identifer, or text
            default:
                return ParsedToken(position: tokStart, line: line, data: nextText())
        }
    }
    
}

extension INITokenizer: Sequence, IteratorProtocol {
    mutating func next() -> ParsedToken? {
        do {
            return try nextToken()
        } catch {
            return nil
        }
    }
}

extension Token: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        switch (self) {
            case .commentMarker(let str): return "commentMarker(\"\(str)\")"
            case .newline: return "newline"
            case .sectionOpen: return "sectionOpen([)"
            case .sectionClose: return "sectionClose(])"
            case .separator: return "separator(=)"
            case .quotedString(let str, let wasDouble): return "quotedString(\"\(str)\", " + (wasDouble ? "double" : "single") + ")"
            case .integer(let str): return "integer(\(str))"
            case .decimal(let str): return "decimal(\(str))"
            case .bareFalse(let str): return "bareFalse(\(str))"
            case .bareTrue(let str): return "bareTrue(\(str))"
            case .whitespace(let str): return "whitespace(\"\(str)\")"
            case .identifier(let str): return "identifier(\"\(str)\")"
            case .text(let str): return "text(\"\(str)\")"
        }
    }

    var debugDescription: String {
        switch (self) {
            case .commentMarker(let str): return ".commentMarker(\"\(str)\")"
            case .newline: return ".newline"
            case .sectionOpen: return ".sectionOpen"
            case .sectionClose: return ".sectionClose"
            case .separator: return ".separator"
            case .quotedString(let str, let wasDouble):
                return ".quotedString(\"" +
                     str.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") +
                "\", doubleQuoted: " + (wasDouble ? "true" : "false") + ")"
            case .integer(let str): return ".integer(\"\(str)\")"
            case .decimal(let str): return ".decimal(\"\(str)\")"
            case .bareFalse(let str): return ".bareFalse(\"\(str)\")"
            case .bareTrue(let str): return ".bareTrue(\"\(str)\")"
            case .whitespace(let str): return ".whitespace(\"\(str)\")"
            case .identifier(let str): return ".identifier(\"\(str)\")"
            case .text(let str): return ".text(\"\(str)\")"
        }
    }
}

extension ParsedToken: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        return "ParsedToken(at \(position.encodedOffset), line \(line), token: \(data)"
    }

    var debugDescription: String {
        return "ParsedToken(position: .init(encodedOffset: \(position.encodedOffset)), line: \(line), data: \(data.debugDescription))"
    }
}
