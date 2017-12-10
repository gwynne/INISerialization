import XCTest
@testable import INISerialization

class INIParserTests: XCTestCase {
    
    func testIdentifierTokens() throws {
        let raw1 = """
            ident1 = valididentifier
            ident2 = valid_identifier
            ident3 = valid-identifier
            ident4 = valid.identifier
        """
        let raw2 = """
            invalid identifier = not-an-identifier
        """
        let relevantOptions: INISerialization.ReadingOptions = [
            .detectNumericValues, .detectSections, .allowHashComments, .allowTrailingComments,
            .detectBooleanValues, .allowMissingValues, .allowSectionReset
        ]
        
        for options in relevantOptions.powerSet() {
            let results1 = try INIParser.parse(raw1, options: options)
            
            XCTAssertEqual(results1["ident1"] as? String, "valididentifier",  "With options \(options.debugDescription), identifier was wrong")
            XCTAssertEqual(results1["ident2"] as? String, "valid_identifier", "With options \(options.debugDescription), identifier was wrong")
            XCTAssertEqual(results1["ident3"] as? String, "valid-identifier", "With options \(options.debugDescription), identifier was wrong")
            XCTAssertEqual(results1["ident4"] as? String, "valid.identifier", "With options \(options.debugDescription), identifier was wrong")
            
            XCTAssertThrowsError(_ = try INIParser.parse(raw2, options: options), "With options \(options.debugDescription), it did not throw an error") {
                guard let err = $0 as? INISerialization.SerializationError else {
                    XCTFail("With options \(options.debugDescription), error \($0) was not a serialization error")
                    return
                }
                guard case .missingSeparator(let line) = err else {
                    XCTFail("With options \(options.debugDescription), \(err) was not a missing separator error")
                    return
                }
                XCTAssertEqual(line, 1, "With options \(options.debugDescription), the error was on the wrong line")
            }
        }
    }
    
    func testNumericTokens() throws {
        let raw1 = """
            ; Numeric token
            num1 = 1
            num2 = 58209
            num3 = -79238
            num4 = 0.6182
            num5 = .112
            num6 = 5.
            """
        
        let results1 = try INIParser.parse(raw1, options: [])
        
        XCTAssertEqual(results1["num1"] as? String, "1")
        XCTAssertEqual(results1["num2"] as? String, "58209")
        XCTAssertEqual(results1["num3"] as? String, "-79238")
        XCTAssertEqual(results1["num4"] as? String, "0.6182")
        XCTAssertEqual(results1["num5"] as? String, ".112")
        XCTAssertEqual(results1["num6"] as? String, "5.")

        let results2 = try INIParser.parse(raw1, options: [.detectNumericValues])

        XCTAssertEqual(results2["num1"] as? UInt, 1)
        XCTAssertEqual(results2["num2"] as? UInt, 58209)
        XCTAssertEqual(results2["num3"] as? Int, -79238)
        XCTAssertEqual(results2["num4"] as? Double, 0.6182)
        XCTAssertEqual(results2["num5"] as? Double, 0.112)
        XCTAssertEqual(results2["num6"] as? Double, 5.0)
    }
    
    func testBooleanTokens() throws {
        let raw1 = """
            bool1 = NO
            bool2 = yes
            bool3 = TruE
            bool4 = fALSe
            """
        
        let results1 = try INIParser.parse(raw1, options: [])
        
        XCTAssertEqual(results1["bool1"] as? String, "NO")
        XCTAssertEqual(results1["bool2"] as? String, "yes")
        XCTAssertEqual(results1["bool3"] as? String, "TruE")
        XCTAssertEqual(results1["bool4"] as? String, "fALSe")

        let results2 = try INIParser.parse(raw1, options: [.detectBooleanValues])

        XCTAssertEqual(results2["bool1"] as? Bool, false)
        XCTAssertEqual(results2["bool2"] as? Bool, true)
        XCTAssertEqual(results2["bool3"] as? Bool, true)
        XCTAssertEqual(results2["bool4"] as? Bool, false)
    }
    
    func testComments() throws {
        let raw1 = """
            ; Isolated semi comment
            k1 = v ; Trailing semi comment
            k2 = v # Trailing hash comment
            k3 = "v ; Quoted semi comment"
            k4 = 'v # Quoted hash comment'
            k5 = "v" ; Trailing quoted semi comment
            k6 = 'v' # Trailing quoted hash comment
            """
        let raw2 = "# Isolated hash comment\n" + raw1
        
        let results1 = try INIParser.parse(raw1, options: [])
        XCTAssertEqual(results1["k1"] as? String, "v ; Trailing semi comment")
        XCTAssertEqual(results1["k2"] as? String, "v # Trailing hash comment")
        XCTAssertEqual(results1["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results1["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results1["k5"] as? String, "\"v\" ; Trailing quoted semi comment")
        XCTAssertEqual(results1["k6"] as? String, "'v' # Trailing quoted hash comment")

        let results2 = try INIParser.parse(raw1, options: [.allowHashComments])
        XCTAssertEqual(results2["k1"] as? String, "v ; Trailing semi comment")
        XCTAssertEqual(results2["k2"] as? String, "v # Trailing hash comment")
        XCTAssertEqual(results2["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results2["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results2["k5"] as? String, "\"v\" ; Trailing quoted semi comment")
        XCTAssertEqual(results2["k6"] as? String, "'v' # Trailing quoted hash comment")

        let results3 = try INIParser.parse(raw1, options: [.allowTrailingComments])
        XCTAssertEqual(results3["k1"] as? String, "v")
        XCTAssertEqual(results3["k2"] as? String, "v # Trailing hash comment")
        XCTAssertEqual(results3["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results3["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results3["k5"] as? String, "v")
        XCTAssertEqual(results3["k6"] as? String, "'v' # Trailing quoted hash comment")

        let results4 = try INIParser.parse(raw1, options: [.allowHashComments, .allowTrailingComments])
        XCTAssertEqual(results4["k1"] as? String, "v")
        XCTAssertEqual(results4["k2"] as? String, "v")
        XCTAssertEqual(results4["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results4["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results4["k5"] as? String, "v")
        XCTAssertEqual(results4["k6"] as? String, "v")
        
        XCTAssertThrowsError(_ = try INIParser.parse(raw2, options: []), "Should throw syntax errror on hash comment when they're not allowed") {
            guard let err = $0 as? INISerialization.SerializationError else {
                XCTFail("Error \($0) was not a serialization error")
                return
            }
            guard case .invalidKeyName(let line) = err else {
                XCTFail("\(err) was not an invalid key name error")
                return
            }
            XCTAssertEqual(line, 1, "The error was on the wrong line")
        }
        
        let results5 = try INIParser.parse(raw2, options: [.allowHashComments])
        XCTAssertEqual(results5["k1"] as? String, "v ; Trailing semi comment")
        XCTAssertEqual(results5["k2"] as? String, "v # Trailing hash comment")
        XCTAssertEqual(results5["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results5["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results5["k5"] as? String, "\"v\" ; Trailing quoted semi comment")
        XCTAssertEqual(results5["k6"] as? String, "'v' # Trailing quoted hash comment")

        let results6 = try INIParser.parse(raw2, options: [.allowHashComments, .allowTrailingComments])
        XCTAssertEqual(results6["k1"] as? String, "v")
        XCTAssertEqual(results6["k2"] as? String, "v")
        XCTAssertEqual(results6["k3"] as? String, "v ; Quoted semi comment")
        XCTAssertEqual(results6["k4"] as? String, "v # Quoted hash comment")
        XCTAssertEqual(results6["k5"] as? String, "v")
        XCTAssertEqual(results6["k6"] as? String, "v")
    }
    
    func testQuotes() throws {
        let raw1 = """
            k1 = "double-quoted"
            k2 = 'single-quoted'
            k3 = "double-quoted with \\"escapes\\""
            k4 = 'single-quoted with \\'escapes\\''
            k5 = "double-quoted with escaped escape\\\\"
            k6 = 'single-quoted with escaped escape\\\\'
            k7 = "double-quoted with mismatched escape\\'"
            k8 = 'single-quoted with mismatched escape\\"'
            """
        
        let results = try INIParser.parse(raw1, options: [])
        
        XCTAssertEqual(results["k1"] as? String, "double-quoted")
        XCTAssertEqual(results["k2"] as? String, "single-quoted")
        XCTAssertEqual(results["k3"] as? String, "double-quoted with \"escapes\"")
        XCTAssertEqual(results["k4"] as? String, "single-quoted with 'escapes'")
        XCTAssertEqual(results["k5"] as? String, "double-quoted with escaped escape\\")
        XCTAssertEqual(results["k6"] as? String, "single-quoted with escaped escape\\")
        XCTAssertEqual(results["k7"] as? String, "double-quoted with mismatched escape\\'")
        XCTAssertEqual(results["k8"] as? String, "single-quoted with mismatched escape\\\"")
        
        let raw2 = "k = \"unterminated double"
        let raw3 = "k = 'unterminated single"
        let raw4 = "k = \"unterminated by mismatched escape\\\""
        
        func handler(_ error: Error) {
            guard let err = error as? INISerialization.SerializationError else { XCTFail("Error \(error) was not serialization error"); return }
            guard case .unterminatedString(let line) = err else { XCTFail("\(err) was not an unterminated string error"); return }
            XCTAssertEqual(line, 1, "The error was on the wrong line")
        }
        XCTAssertThrowsError(_ = try INIParser.parse(raw2, options: []), "Should throw syntax error", handler)
        XCTAssertThrowsError(_ = try INIParser.parse(raw3, options: []), "Should throw syntax error", handler)
        XCTAssertThrowsError(_ = try INIParser.parse(raw4, options: []), "Should throw syntax error", handler)
    }
    
    func testSections() throws {
        let raw1 = """
            [SECTION]
            k = v
            """
        
        XCTAssertThrowsError(_ = try INIParser.parse(raw1, options: []), "Should throw syntax error with sections disabled") {
            guard let err = $0 as? INISerialization.SerializationError else { XCTFail("Error \($0) was not serialization error"); return }
            guard case .sectionsNotAllowed(let line) = err else { XCTFail("\(err) was not a sections error"); return }
            XCTAssertEqual(line, 1, "The error was on the wrong line")
        }
        
        let results1 = try INIParser.parse(raw1, options: [.detectSections])
        let sect = results1["SECTION"] as? [String: Any]
        
        XCTAssertNotNil(sect)
        XCTAssertEqual(sect?["k"] as? String, "v")
        
        let raw2 = """
            k = u
            [SECTION1]
            k = v
            [SECTION2]
            k = w
            """
        let results2 = try INIParser.parse(raw2, options: [.detectSections])
        let sect1 = results2["SECTION1"] as? [String: Any]
        let sect2 = results2["SECTION2"] as? [String: Any]
        
        XCTAssertEqual(results2["k"] as? String, "u")
        XCTAssertNotNil(sect1)
        XCTAssertEqual(sect1?["k"] as? String, "v")
        XCTAssertNotNil(sect2)
        XCTAssertEqual(sect2?["k"] as? String, "w")

        let raw3 = """
            [SECTION]
            k = v
            []
            k = 1
            """
        
        XCTAssertThrowsError(_ = try INIParser.parse(raw3, options: [.detectSections]), "Should throw syntax error with section reset disabled") {
            guard let err = $0 as? INISerialization.SerializationError else { XCTFail("Error \($0) was not serialization error"); return }
            guard case .tooManyBrackets(let line) = err else { XCTFail("\(err) was not a brackets error"); return }
            XCTAssertEqual(line, 3, "The error was on the wrong line")
        }
        
        let results4 = try INIParser.parse(raw3, options: [.detectSections, .allowSectionReset])
        let sectagain = results4["SECTION"] as? [String: Any]
        
        XCTAssertNotNil(sectagain)
        XCTAssertEqual(sectagain?["k"] as? String, "v")
        XCTAssertEqual(results4["k"] as? String, "1")
    }
    
    static var allTests = [
        ("testIdentifierTokens", testIdentifierTokens),
        ("testNumericTokens", testNumericTokens),
        ("testBooleanTokens", testBooleanTokens),
        ("testComments", testComments),
        ("testQuotes", testQuotes),
        ("testSections", testSections),
    ]
}
