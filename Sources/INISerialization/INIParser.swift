//
//  INIParser.swift
//  INISerialization
//
//  Created by Gwynne Raskind on 12/5/17.
//

import Foundation

internal class INIParser {
    typealias Lex = () throws -> ParsedToken?
    
    let options: INISerialization.ReadingOptions
    let tokenizer: Lex
    
    // - MARK: "External" interface
    
    class func parse(_ text: String, options: INISerialization.ReadingOptions = []) throws -> [String: Any] {
        var tokenizer = INITokenizer(text)
        
        return try INIParser(options: options) { try tokenizer.nextToken() }.parse()
    }
    
    // - MARK: Guts
    
    private init(options: INISerialization.ReadingOptions, lexer: @escaping Lex) {
        self.options = options
        self.tokenizer = lexer
    }
    
    enum State: Equatable {
        case inSection(name: String?) // A section header was read and we're looking for keys, or top level
        case readingSectionHeader // Saw a [ but nothing else
        case finishingSectionHeader(name: String) // Saw a section name after [, waiting for ]
        case awaitingSectionStart(name: String?) // Got ], waiting for comment or eol
        case readingKey(key: String) // Read a key but no separator
        case readingValue(key: String, valueSoFar: [Token]) // Read a separator and are gathering value fragments
        case readingComment(tokens: [Token]) // Read a comment marker in a valid place and are waiting for newline

        static func ==(lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
                case (.readingSectionHeader, .readingSectionHeader):                    return true
                case (.finishingSectionHeader(let l), .finishingSectionHeader(let r)):  return l == r
                case (.awaitingSectionStart(let l), .awaitingSectionStart(let r)):      return l == r
                case (.inSection(let l), .inSection(let r)):                            return l == r
                case (.readingKey(let l), .readingKey(let r)):                          return l == r
                case (.readingComment(let l), .readingComment(let r)):                  return l == r
                case (.readingValue(let k1, let v1), .readingValue(let k2, let v2)):    return k1 == k2 && v1 == v2
                default: return false
            }
        }
        
        func `is`(rhs: State) -> Bool {
            switch (self, rhs) {
                case (.readingSectionHeader,   .readingSectionHeader),
                     (.finishingSectionHeader, .finishingSectionHeader),
                     (.awaitingSectionStart,   .awaitingSectionStart),
                     (.inSection,              .inSection),
                     (.readingKey,             .readingKey),
                     (.readingValue,           .readingValue),
                     (.readingComment,         .readingComment):
                    return true
                default:
                    return false
            }
        }
    }
    
    func parse() throws -> [String: Any] {
        var lastLoc: String.Index = String.Index(encodedOffset: 0)
        var lastLine: UInt = 0
        
        while let tok = try tokenizer() {
            lastLoc = tok.position
            lastLine = tok.line
            
            switch tok.data {
                case .commentMarker: try handleCommentMarker(tok)
                case .newline: try handleNewline(tok)
                case .sectionOpen: try handleSectionOpen(tok)
                case .sectionClose: try handleSectionClose(tok)
                case .separator: try handleSeparator(tok)
                case .quotedString: try handleQuotedString(tok)
                case .signedInteger, .unsignedInteger: try handleInteger(tok)
                case .decimal: try handleDecimal(tok)
                case .bareTrue, .bareFalse: try handleBoolean(tok)
                case .whitespace: try handleWhitespace(tok)
                case .identifier(let str): try handleIdentifier(tok, String(str))
                case .text: try handleText(tok)
            }
            
//            print("Token: \(tok.data)\nStack: " + stack.map { $0.debugDescription }.joined(separator: ", "))
        }
        // Implicit newline at the end of input to pop anything still on the stack
        try handleNewline(.init(position: lastLoc, line: lastLine, data: .newline))
        return result
    }
    
    var stack: [State] = [.inSection(name: nil)]
    var line: UInt = 1
    var result: [String: Any] = [:]
    
    var topState: State { return stack.last! }
    func popState() { _ = stack.popLast() }
    func pushState(_ newState: State) { stack.append(newState) }
    func replaceState(with newState: State) {
        popState()
        pushState(newState)
    }
    func addStateToken(_ token: ParsedToken) {
        switch topState {
        	case .readingValue(let key, let valuesSoFar): replaceState(with: .readingValue(key: key, valueSoFar: valuesSoFar + [token.data]))
            case .readingComment(let tokens): replaceState(with: .readingComment(tokens: tokens + [token.data]))
            default: fatalError("Can only add tokens to values or comments")
        }
    }
    
    func setTrueValue(_ value: Any, forKey key: String) {
        guard case .inSection(let maybeSect) = stack.first! else { fatalError("base state is not a section state") }
        
        let finalKey = options.contains(.lowercaseKeys) ? key.lowercased() : (options.contains(.uppercaseKeys) ? key.uppercased() : key)
        
        if let sect = maybeSect {
            let finalSect = options.contains(.lowercaseKeys) ? sect.lowercased() : (options.contains(.uppercaseKeys) ? sect.uppercased() : sect)
            
            if var existing = result[finalSect] as? [String: Any] {
                existing[finalKey] = value
                result[finalSect] = existing
            } else {
                result[finalSect] = [finalKey: value]
            }
        } else {
            result[finalKey] = value
        }
    }
    
    func recordKeyAndValue(key: String, value: [Token]?) throws {
        if let values = value {
            // This is a not-terribly-efficient trim()
            func dropWhite(_ tok: Token) -> Bool { if case .whitespace = tok { return true } else { return false } }
            let filteredValues = values.drop(while: dropWhite).reversed().drop(while: dropWhite).reversed()
            
            if filteredValues.count == 0 {
                setTrueValue("", forKey: key)
            } else if filteredValues.count == 1 {
                switch filteredValues.first! {
                    case .commentMarker(let content): setTrueValue(String(content), forKey: key)
                    case .newline: fatalError("newline token should never appear in value token list")
                    case .sectionOpen: setTrueValue("[", forKey: key)
                    case .sectionClose: setTrueValue("]", forKey: key)
                    case .separator: setTrueValue("=", forKey: key)
                    case .quotedString(let str, _): setTrueValue(String(str), forKey: key)
                    case .signedInteger(let str): setTrueValue(options.contains(.detectNumericValues) ? Int(str)! : String(str), forKey: key)
                    case .unsignedInteger(let str): setTrueValue(options.contains(.detectNumericValues) ? UInt(str)! : String(str), forKey: key)
                    case .decimal(let str): setTrueValue(options.contains(.detectNumericValues) ? Double(str)! : String(str), forKey: key)
                    case .bareFalse(let str): setTrueValue(options.contains(.detectBooleanValues) ? false : String(str), forKey: key)
                    case .bareTrue(let str): setTrueValue(options.contains(.detectBooleanValues) ? true : String(str), forKey: key)
                    case .whitespace: fatalError("sole whitespace token should have been filtered out")
                    case .identifier(let str): setTrueValue(String(str), forKey: key)
                    case .text(let str): setTrueValue(String(str), forKey: key)
                }
            } else {
                var intermediate = ""
                
                for token in filteredValues {
                    switch token {
                        case .commentMarker(let content): intermediate += content
                        case .newline: fatalError("newline token should never appear in value token list")
                        case .sectionOpen: intermediate += "["
                        case .sectionClose: intermediate += "]"
                        case .separator: intermediate += "="
                        case .quotedString(let str, let isDouble): // When a quoted string appears in a set of value tokens, the quotes lose their magic
                            intermediate += (isDouble ? "\"" : "'") + str + (isDouble ? "\"" : "'")
                        case .signedInteger(let str): intermediate += str
                        case .unsignedInteger(let str): intermediate += str
                        case .decimal(let str): intermediate += str
                        case .bareFalse(let str): intermediate += str
                        case .bareTrue(let str): intermediate += str
                        case .whitespace(let str): intermediate += str
                        case .identifier(let str): intermediate += str
                        case .text(let str): intermediate += str
                    }
                }
                setTrueValue(intermediate, forKey: key)
            }
        } else {
            setTrueValue("", forKey: key)
        }
//        print("KEY: \(key)\nVALUE: \(value ?? [.text("MISSING")])")
    }
    
    func handleCommentMarker(_ tok: ParsedToken) throws {
        // inSection -> readingComment
        // readingSectionHeader -> ERROR
        // finishingSectionHeader -> ERROR
        // awaitingSectionStart -> readingComment
        // readingKey -> ERROR, ^readingComment
        // readingValue -> readingValue, ^readingComment
        // readingComment -> readingComment
        guard case .commentMarker(let marker) = tok.data else { fatalError("not a comment marker") }
        if marker == "#" && !options.contains(.allowHashComments) {
            try handleText(tok) // If we're not allowing hash comments, a hash marker is treated as a text node
            return
        }
        switch topState {
            case .inSection: // Comment marker at top level starts a comment
                pushState(.readingComment(tokens: [tok.data]))
            case .readingSectionHeader, .finishingSectionHeader:
                throw INISerialization.SerializationError.commentInSectionHeader(line: tok.line)
            case .awaitingSectionStart:
                if !options.contains(.allowTrailingComments) {
                    throw INISerialization.SerializationError.commentInSectionHeader(line: tok.line)
                }
                replaceState(with: .readingComment(tokens: [tok.data]))
            case .readingKey(let key):
                if !options.contains(.allowTrailingComments) {
                    throw INISerialization.SerializationError.commentInterruptedKey(line: tok.line)
                }
                if !options.contains(.allowMissingValues) {
                    throw INISerialization.SerializationError.incompleteKey(line: tok.line)
                }
                try recordKeyAndValue(key: key, value: nil)
            case .readingValue(let key, let value):
                if !options.contains(.allowTrailingComments) {
                    addStateToken(tok)
                } else {
                    try recordKeyAndValue(key: key, value: value)
                    replaceState(with: .readingComment(tokens: [tok.data]))
                }
            case .readingComment:
                addStateToken(tok)
        }
    }
    
    func handleNewline(_ tok: ParsedToken) throws {
        // inSection -> inSection
        // readingSectionHeader -> ERROR
        // finishingSectionHeader -> ERROR
        // awaitingSectionStart -> ^inSection
        // readingKey -> ERROR, ^
        // readingValue -> ERROR, ^
        // readingComment -> ^
        switch topState {
            case .inSection: // Newlines always valid at top level
                break
            case .readingSectionHeader, .finishingSectionHeader: // Newline never valid while reading section name or closer
                throw INISerialization.SerializationError.incompleteSectionHeader(line: tok.line)
            case .awaitingSectionStart(let name): // Newline is valid when about to start a section
                popState() // remove the await
                replaceState(with: .inSection(name: name)) // Replace top level state with current
            case .readingKey(let key):
                if !options.contains(.allowMissingValues) { // To accept EOL here, must be allowing missing values
                    throw INISerialization.SerializationError.incompleteKey(line: tok.line)
                }
                try recordKeyAndValue(key: key, value: nil)
                popState() // Pop the .ReadingKey state
            case .readingValue(let key, let value):
                try recordKeyAndValue(key: key, value: value) // Ended the value
                popState() // Pop the .ReadingValue state
            case .readingComment: // Ends the comment
                // We don't do anything with comments, so just pop it into nowhere
                popState()
        }
    }
    
    func handleSectionOpen(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, readingKey -> ERROR
        // inSection -> ^readingSectionHeader
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .inSection: // Section open at top level may be valid
                if !options.contains(.detectSections) { // .detectSections must be set to use sections
                    throw INISerialization.SerializationError.sectionsNotAllowed(line: tok.line) // hard error at top level
                }
                pushState(.readingSectionHeader)
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .readingKey: // If already reading/read a section header or key, syntax error
                throw INISerialization.SerializationError.tooManyBrackets(line: tok.line)
            case .readingValue, .readingComment: // Section header start while reading value or comment becomes part of the token list
                addStateToken(tok)
        }
    }
    
    func handleSectionClose(_ tok: ParsedToken) throws {
        // awaitingSectionStart, inSection, readingKey -> ERROR
        // readingSectionHeader -> ERROR, ^awaitingSectionStart
        // finishingSectionHeader -> ^awaitingSectionStart
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader: // Section close with no section name may be valid
                if !options.contains(.allowSectionReset) { // .allowSectionReset must be set to reset section name
                    throw INISerialization.SerializationError.tooManyBrackets(line: tok.line)
                }
                replaceState(with: .awaitingSectionStart(name: nil)) // Add the await so comments can be processed and no more syntax happens
            case .finishingSectionHeader(let name): // Section close with section name starts new section
                replaceState(with: .awaitingSectionStart(name: name)) // Go to waiting for comment/newline
            case .awaitingSectionStart, .inSection, .readingKey: // Section closer when awaiting, at section level, or reading key is syntax error
                throw INISerialization.SerializationError.tooManyBrackets(line: tok.line)
            case .readingValue, .readingComment: // Section header closer while reading value or comment becomes part of the token list
                addStateToken(tok)
        }
    }
    
    func handleSeparator(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection -> ERROR
        // readingKey -> ^readingValue
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .inSection: // Separator at top or section header is syntax error
                throw INISerialization.SerializationError.noKeyAvailable(line: tok.line)
            case .readingKey(let key): // Separator while reading key starts value read
                replaceState(with: .readingValue(key: key, valueSoFar: [])) // Push an empty value state
            case .readingValue, .readingComment: // Separator while reading value or comment becomes part of the token list
                addStateToken(tok)
        }
    }
    
    func handleQuotedString(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .inSection, .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .readingKey: // In top, section, header, key is error
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Quoted string while reading value or comment is valid
                addStateToken(tok)
        }
    }
    
    func handleInteger(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .inSection, .readingKey: // Syntax error if not reading value
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Integer while reading value or comment is valid
                addStateToken(tok)
        }
    }
    
    func handleDecimal(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .inSection, .readingKey: // Syntax error if not reading value
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Decimal while reading value or comment is valid
                addStateToken(tok)
        }
    }

    func handleBoolean(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .inSection, .readingKey: // Syntax error if not reading value
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Boolean while reading value or comment is valid
                addStateToken(tok)
        }
    }
    
    func handleWhitespace(_ tok: ParsedToken) throws {
        // readingSectionHeader, finishingSectionHeader, awaitingSectionStart, inSection, readingKey ->
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart, .inSection, .readingKey: // Whitespace is ignored most places
                break
            case .readingValue, .readingComment: // Whitespace while reading value or comment is significant
                addStateToken(tok)
        }
    }
    
    func handleIdentifier(_ tok: ParsedToken, _ str: String) throws {
        // inSection -> readingKey
        // readingSectionHeader -> ^finishingSectionHeader
        // finishingSectionHeader, awaitingSectionStart, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .inSection: // Identifier at top level starts a key
                pushState(.readingKey(key: str)) // do NOT pop top-level state
            case .readingSectionHeader: // Identifier in section header sets section name
                replaceState(with: .finishingSectionHeader(name: str))
            case .finishingSectionHeader, .awaitingSectionStart: // Identifier after section header is syntax error
                throw INISerialization.SerializationError.invalidSectionName(line: tok.line)
            case .readingKey: // Identifier while waiting for separator is syntax error
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Identifier while reading value or comment is valid
                addStateToken(tok)
        }
    }
    
    func handleText(_ tok: ParsedToken) throws {
        // inSection, readingSectionHeader, finishingSectionHeader, awaitingSectionStart, readingKey -> ERROR
        // readingValue -> readingValue
        // readingComment -> readingComment
        switch topState {
            case .inSection: // Text at top level is syntax error
                throw INISerialization.SerializationError.invalidKeyName(line: tok.line)
            case .readingSectionHeader, .finishingSectionHeader, .awaitingSectionStart: // Text in or after section header is syntax error
                throw INISerialization.SerializationError.invalidSectionName(line: tok.line)
            case .readingKey: // Text while waiting for separator is syntax error
                throw INISerialization.SerializationError.missingSeparator(line: tok.line)
            case .readingValue, .readingComment: // Text while reading value or comment is valid
                addStateToken(tok)
        }
    }
}

extension INIParser.State: CustomDebugStringConvertible {
    var debugDescription: String {
        switch (self) {
            case .readingSectionHeader: return "readingSectionHeader"
            case .finishingSectionHeader(let name): return "finishingSectionHeader(\(name))"
            case .awaitingSectionStart(let name): return "awaitingSectionStart(\(name ?? "RESET"))"
            case .inSection(let name): return "inSection(\(name ?? "(NONE)"))"
            case .readingKey(let key): return "readingKey(\(key))"
            case .readingValue(let key, let value): return "readingValue(\(key), " + value.map { $0.debugDescription }.joined(separator: ",") + ")"
            case .readingComment(let tokens): return "readingComment(" + tokens.map { $0.debugDescription }.joined(separator: ",") + ")"
        }
    }
}

