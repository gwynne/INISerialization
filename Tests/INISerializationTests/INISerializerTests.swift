import XCTest
@testable import INISerialization

/// Just testing that the public serializer interface is hooked up sanely. The
/// real functionality tests are covered by the tests of the internal classes.
class INISerializerTests: XCTestCase {

    func testIniObject() throws {
        let obj = try INISerialization.iniObject(with: """
            hello = world
            
            [SECTION]
            monty = python
            
            """.data(using: .utf8)!, encoding: .utf8, options: [.detectSections]
        )
        
        XCTAssertEqual(obj["hello"] as? String, "world")
        XCTAssertNotNil(obj["SECTION"] as? [String: Any])
        XCTAssertNotNil((obj["SECTION"] as? [String: Any])?["monty"] as? String, "python")
    }
    
    func testData() throws {
        let obj = try INISerialization.data(withIniObject: [
            "hello": "world",
            "SECTION": [
                "monty": "python"
            ]
        ], encoding: .utf8, options: [])
        
        XCTAssertEqual(obj, """
            hello = world
            [SECTION]
            monty = python
            
            """.data(using: .utf8)!, "returned the right data")
    }
    
    static var allTests = [
        ("testIniObject", testIniObject),
        ("testData", testData),
    ]
}
