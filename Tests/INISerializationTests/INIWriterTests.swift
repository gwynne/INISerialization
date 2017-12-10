import XCTest
@testable import INISerialization

/// - TODO: Figure out a way to test meaningfully with unordered objects, since
/// we can't control the key iteration order and therefore would have to get
/// creative with parsing the resulting output for correctness.
class INIWriterTests: XCTestCase {
    
    private func runTest<T, E>(withData data: T, throwing: E, file: StaticString = #file, line: UInt = #line) throws
    		where E: Error & Equatable, T: Sequence, T.Element == INIKeyValuePair
    {
        XCTAssertThrowsError(try INIWriter().serialize(data), "Serializer should have thrown \(throwing)") {
            guard $0 is E else {
            	XCTFail("Serializer should have thrown error of type \(E.self) but threw \(type(of: $0).self)")
                return
            }
            XCTAssertEqual(throwing, $0 as! E, "Serializer threw \($0) instead of \(throwing)")
        }
    }

    private func runTest<T>(withData data: T, expecting: String, file: StaticString = #file, line: UInt = #line) throws
            where T: Sequence, T.Element == INIKeyValuePair
    {
        let result = try INIWriter().serialize(data)
        XCTAssertEqual(expecting, result, "Serializer generated the wrong text", file: file, line: line)
    }
    
    func testBasicWrite() throws {
        try runTest(withData: [
            "key": "value"
        ], expecting: """
            key = value
            
            """
        )
    }
    
    func testDataTypes() throws {
        try runTest(withData: INIOrderedObject([
            INIKeyValuePair("meta", "meta"),
            ("idKey", "valid-identifier"),
            ("textKey", "Definitely ⓝⓞⓣ a valid 🅘🅓🅔🅝🅣🅘🅕🅘🅔🅡‼️‼️ 😉🙃"),
            ("int8Key", Int8.min),
            ("uint8Key", UInt8.max),
            ("int16Key", Int16.min),
            ("uint16Key", UInt16.max),
            ("int32Key", Int32.min),
            ("uint32Key", UInt32.max),
            ("int64Key", Int64.min),
            ("uint64Key", UInt64.max),
            ("intKey", Int.min),
            ("uintKey", UInt.max),
            ("floatKey", Float.greatestFiniteMagnitude),
            ("doubleKey", Double.greatestFiniteMagnitude),
            ("trueKey", true),
            ("falseKey", false),
        ]), expecting: """
            meta = meta
            idKey = valid-identifier
            textKey = "Definitely ⓝⓞⓣ a valid 🅘🅓🅔🅝🅣🅘🅕🅘🅔🅡‼️‼️ 😉🙃"
            int8Key = \(Int8.min)
            uint8Key = \(UInt8.max)
            int16Key = \(Int16.min)
            uint16Key = \(UInt16.max)
            int32Key = \(Int32.min)
            uint32Key = \(UInt32.max)
            int64Key = \(Int64.min)
            uint64Key = \(UInt64.max)
            intKey = \(Int.min)
            uintKey = \(UInt.max)
            floatKey = \(Float.greatestFiniteMagnitude)
            doubleKey = \(Double.greatestFiniteMagnitude)
            trueKey = true
            falseKey = false
            
            """
        )
        
        try runTest(withData: [
            "dateKey": Date()
        ], throwing: INISerialization.SerializationError.unsupportedType(keyPath: "dateKey", type: Date.self))
    }
    
    func testKeyValidity() throws {
        try runTest(withData: [
            "invalid key": "value"
        ], throwing: INISerialization.SerializationError.invalidIdentifier(keyPath: "invalid key"))
        
        try runTest(withData: [
            "valid-key": true,
            "invalid+key": false,
        ], throwing: INISerialization.SerializationError.invalidIdentifier(keyPath: "invalid+key"))
        
        try runTest(withData: [
            "validkey": true,
            "section": [
                "invalid key": false,
            ],
        ], throwing: INISerialization.SerializationError.invalidIdentifier(keyPath: "section.invalid key"))
    }
    
    func testIsolatedSections() throws {
        // So unnecessarily verbose, just 'cause the compiler can't do one extra
        // level of inference (without at least one INIKeyValuePair() in the
        // value list, it complains the type is ambiguous and needs context).
        try runTest(withData: INIOrderedObject([
            INIKeyValuePair("section", INIOrderedObject([
                INIKeyValuePair("yes", true),
                INIKeyValuePair("no", false),
            ])),
            INIKeyValuePair("meta", INIOrderedObject([
                INIKeyValuePair("I", "am"),
                INIKeyValuePair("so", "ⓜⓔⓣⓐ"),
            ])),
        ]), expecting: """
            [section]
            yes = true
            no = false
            [meta]
            I = am
            so = "ⓜⓔⓣⓐ"
            
            """
        )
    }
    
    func testKeysWithSections() throws {
        try runTest(withData: INIOrderedObject([
            INIKeyValuePair("section", INIOrderedObject([
                INIKeyValuePair("hello", "there"),
                INIKeyValuePair("its", "Monty Python's Flying Circus!"),
            ])),
            INIKeyValuePair("second", "really?"),
            INIKeyValuePair("first", "nope"),
        ]), expecting: """
            second = "really?"
            first = nope
            [section]
            hello = there
            its = "Monty Python's Flying Circus!"
            
            """
        )
    }
    
    func testNesting() throws {
        try runTest(withData: [
            "foo": [
                "bar": [
                    "baz": "oops"
                ]
            ]
        ], throwing: INISerialization.SerializationError.nestedTooDeep(keyPath: "foo.bar"))
    }
    
    static var allTests = [
        ("testBasicWrite", testBasicWrite),
        ("testDataTypes", testDataTypes),
        ("testKeyValidity", testKeyValidity),
        ("testIsolatedSections", testIsolatedSections),
        ("testKeysWithSections", testKeysWithSections),
        ("testNesting", testNesting),
    ]
}
