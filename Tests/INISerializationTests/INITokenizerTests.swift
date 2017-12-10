import XCTest
@testable import INISerialization

extension ParsedToken {
    init(at offset: Int, line: UInt, _ data: Token) {
        self.init(position: .init(encodedOffset: offset), line: line, data: data)
    }
}

// No, this does not result in enormously readable test cases.
// But it does result in test samples that don't take up 5 screens for one line
// of INI file.
class QuickTokens {
    var tokens: [ParsedToken] { return result }

    func cmnt(_ c: String) -> QuickTokens   { add(.commentMarker(c)); pos += 1; return self }
    func uret() -> QuickTokens              { add(.newline); pos += 1; line += 1; return self }
    func wret() -> QuickTokens              { add(.newline); pos += 2; line += 1; return self }
    func idnt(_ idt: String) -> QuickTokens { add(.identifier(subs(idt))); pos += idt.count; return self }
    func sepr() -> QuickTokens              { add(.separator); pos += 1; return self }
    func spac(_ s: String) -> QuickTokens   { add(.whitespace(subs(s))); pos += s.count; return self }
    func seco() -> QuickTokens              { add(.sectionOpen); pos += 1; return self }
    func secc() -> QuickTokens              { add(.sectionClose); pos += 1; return self }
    func intr(_ i: Int) -> QuickTokens      { let s = String(i); add(.integer(subs(s))); pos += s.count; return self }
    func decl(_ d: Double) -> QuickTokens   { let s = String(d); add(.decimal(subs(s))); pos += s.count; return self }
    func dquo(_ s: String) -> QuickTokens   { add(.quotedString(s, doubleQuoted: true)); pos += esclen(s, "\"") + 2; return self }
    func squo(_ s: String) -> QuickTokens   { add(.quotedString(s, doubleQuoted: false)); pos += esclen(s, "'") + 2; return self }
    func bfls(_ b: String) -> QuickTokens   { add(.bareFalse(subs(b))); pos += b.count; return self }
    func btru(_ b: String) -> QuickTokens   { add(.bareTrue(subs(b))); pos += b.count; return self }
    func text(_ t: String) -> QuickTokens   { add(.text(subs(t))); pos += t.count; return self }

    private var result: [ParsedToken] = []
    private var pos: Int = 0, line: UInt = 1
    
    private func add(_ token: Token) {
        result.append(.init(at: pos, line: line, token))
    }
    private func esclen(_ s: String, _ q: String) -> String.IndexDistance {
        return s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: q, with: "\\" + q).count
    }
    private func subs(_ s: String) -> Substring {
        return s[s.startIndex..<s.endIndex]
    }
}
typealias QT = QuickTokens

struct INITokenizerTest: CustomStringConvertible {
    let input: String
    let result: Result
    
    enum Result { case Tokens(QT), Error(Error) }
    
    init(_ input: String, _ result: Result) {
        self.input = input
        self.result = result
    }
    
    static func t(_ input: String, _ tokens: QT) -> INITokenizerTest {
        return INITokenizerTest(input, Result.Tokens(tokens))
    }
    static func t(_ input: String, _ error: Error) -> INITokenizerTest {
        return INITokenizerTest(input, Result.Error(error))
    }
    
    public var description: String {
        var desc = ""
        
        desc += "INPUT:\n\(input)\n"
        desc += "EXPECTED:"
        switch result {
            case .Error(let e):
                desc += " ERROR(\(e))"
            case .Tokens(let t):
                desc += "\n"
                for tok in t.tokens {
                    desc += String(format: "\t@%2u:%3u - %@\n", tok.line, tok.position.encodedOffset, tok.data.debugDescription)
                }
        }
        return desc
    }
}

extension Array where Element == ParsedToken {
    public var tokenListDescription: String {
        var desc = ""

        for tok in self {
            desc += String(format: "\t@%2u:%3u - %@\n", tok.line, tok.position.encodedOffset, tok.data.debugDescription)
        }
        return desc
    }
}

class INITokenizerTests: XCTestCase {

    func runTokenizerTestSet(_ tests: [INITokenizerTest], file: StaticString = #file, line: UInt = #line) throws {
        for (i, test) in tests.enumerated() {
            switch test.result {
                case .Error:
                    var results: [ParsedToken] = []
                    
                    XCTAssertThrowsError(
                        results = try INITokenizer.tokenize(test.input),
                        "Test \(i + 1) of \(tests.count) should throw, but didn't. Test is:\n\(test)\nResult:\n\(results.tokenListDescription)", file: file, line: line)
                    { err in
                        //XCTAssertEqual(error, err, "Test \(i + 1) of \(tests.count) threw the wrong error (expected \(error), got \(err))")
                    }
                    XCTAssertEqual(results.count, 0, "Results array should be empty", file: file, line: line)
                case .Tokens(let tokens):
                    do {
                        let results = try INITokenizer.tokenize(test.input)
                        
                        XCTAssertEqual(results, tokens.tokens, "Test \(i + 1) of \(tests.count) compare failure. Test is:\n\(test)\nResult:\n\(results.tokenListDescription)", file: file, line: line)
                    } catch {
                        XCTFail("Test \(i + 1) of \(tests.count) threw \(error) (it wasn't supposed to). Test is:\n\(test)", file: file, line: line)
                    }
            }
        }
    }

    func testTokenizerBasic() throws {
        try runTokenizerTestSet([
            .t("; Comment\nkey1 = value1\nkey2 = value2\n", QT()
                    .cmnt(";").spac(" ").idnt("Comment").uret()
                    .idnt("key1").spac(" ").sepr().spac(" ").idnt("value1").uret()
                    .idnt("key2").spac(" ").sepr().spac(" ").idnt("value2").uret())
        ])
    }
    
    func testTokenizerComments() throws {
        let tests = [
            "; C1\n; C2\nk=v ; C3",
            "# C1\n# C2\nk=v # C3",
            "; C1\n# C2\nk=v ; C3",
            "# C1\n; C2\nk=v # C3",
        ]
        try runTokenizerTestSet([
            .t(tests[0], QT().cmnt(";").spac(" ").idnt("C1").uret()
                             .cmnt(";").spac(" ").idnt("C2").uret()
                             .idnt("k").sepr().idnt("v").spac(" ")
                             .cmnt(";").spac(" ").idnt("C3")),
            .t(tests[1], QT().cmnt("#").spac(" ").idnt("C1").uret()
                             .cmnt("#").spac(" ").idnt("C2").uret()
                             .idnt("k").sepr().idnt("v").spac(" ").cmnt("#").spac(" ").idnt("C3")),
            .t(tests[2], QT().cmnt(";").spac(" ").idnt("C1").uret()
                             .cmnt("#").spac(" ").idnt("C2").uret()
                             .idnt("k").sepr().idnt("v").spac(" ")
                             .cmnt(";").spac(" ").idnt("C3")),
            .t(tests[3], QT().cmnt("#").spac(" ").idnt("C1").uret()
                             .cmnt(";").spac(" ").idnt("C2").uret()
                             .idnt("k").sepr().idnt("v").spac(" ").cmnt("#").spac(" ").idnt("C3")),
        ])
    }
    
    func testTokenizerSections() throws {
        try runTokenizerTestSet([
            .t("[S1]\nk=v\n[S2]\nv=k", QT().seco().idnt("S1").secc().uret()
                                           .idnt("k").sepr().idnt("v").uret()
                                           .seco().idnt("S2").secc().uret()
                                           .idnt("v").sepr().idnt("k"))
        ])
    }
    
    func testTokenizerQuoting() throws {
        // These quickly get very confusing due to the double-escaping.
        // Unfortunately, Swift doesn't let you cheat with single-quoted strings
        try runTokenizerTestSet([
            .t("\"v\"",        QT().dquo("v")),
            .t("'v'",          QT().squo("v")),
            .t("\"\\\"\\\"\"", QT().dquo("\"\"")),
            .t("'\\'\\''",     QT().squo("''")),
            .t("\"\\\"\"",     QT().dquo("\"")),
            
            .t("'",            INISerialization.SerializationError.unterminatedString(line: 1)),
            .t("\"",           INISerialization.SerializationError.unterminatedString(line: 1)),
            .t("\"\\\\\"\"",   INISerialization.SerializationError.unterminatedString(line: 1)),
            .t("'\\\\''",      INISerialization.SerializationError.unterminatedString(line: 1)),
            
            .t("\"this is a quoted string\"", QT().dquo("this is a quoted string")),
            .t("'this is a quoted string'",   QT().squo("this is a quoted string")),
        ])
    }
    
    func testTokenizerBooleans() throws {
        func boolTests(_ input: String, btoken: (String) -> QT) -> [INITokenizerTest] {
            let upper = input.uppercased(),
                ucfirst = String(input.first!).uppercased() + input.dropFirst(),
                dquo = "\"\(input)\"",
                squo = "'\(input)'",
                suquo = "'\(ucfirst)'"
            
            return [
                .t(input,   btoken(input)),
                .t(upper,   btoken(upper)),
                .t(ucfirst, btoken(ucfirst)),
                .t(dquo,    QT().dquo(input)),
                .t(squo,    QT().squo(input)),
                .t(suquo,   QT().squo(ucfirst))
            ]
        }
        try runTokenizerTestSet([
            .t("0",     QT().intr(0)),
            .t("\"0\"", QT().dquo("0")),
            .t("'0'",   QT().squo("0")),
            .t("1",     QT().intr(1)),
            .t("\"1\"", QT().dquo("1")),
            .t("'1'",   QT().squo("1")),
        ]
            + boolTests("false") { QT().bfls($0) }
            + boolTests("true")  { QT().btru($0) }
            + boolTests("no")    { QT().bfls($0) }
            + boolTests("yes")   { QT().btru($0) }
        )
    }
    
    func testTokenizerNumerics() throws {
        for n in [0, 1, Int(UInt32.max), Int.max, Int(Int32.min), Int(Int64.min), Int.min] {
            let s = "\(n)", q = "'\(n)'"
            try runTokenizerTestSet([.t(s, QT().intr(Int(s)!)), .t(q, QT().squo(s))])
        }

        for n in [0.0, 1.0, 2.5, Double.leastNormalMagnitude] {
            let s = "\(n)", q = "'\(n)'"
            try runTokenizerTestSet([.t(s, QT().decl(Double(s)!)), .t(q, QT().squo(s))])
        }
        for n in [Double.nan, Double.infinity] {
            let s = "\(n)", q = "'\(n)'"
            try runTokenizerTestSet([.t(s, QT().decl(Double(s)!)), .t(q, QT().squo(s))])
        }
        let s = "\(Double.greatestFiniteMagnitude)", q = "'\(Double.greatestFiniteMagnitude)'"
        try runTokenizerTestSet([.t(s, QT().text(s)), .t(q, QT().squo(s))])
    }

    static var allTests = [
        ("testTokenizerBasic", testTokenizerBasic),
        ("testTokenizerComments", testTokenizerComments),
        ("testTokenizerSections", testTokenizerSections),
        ("testTokenizerBooleans", testTokenizerBooleans),
        ("testTokenizerNumerics", testTokenizerNumerics),
    ]
}
