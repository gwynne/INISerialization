import XCTest
@testable import INISerialization

struct INITest: Codable {
    struct integersTest: Codable {
        let tiny_s: Int8
        let tiny_u: UInt8
        let small_s: Int16
        let small_u: UInt16
        let large_s: Int32
        let large_u: UInt32
        let huge_s: Int64
        let huge_u: UInt64
    }
    struct decimalsTest: Codable {
        let small: Float
        let large: Double
    }
    struct otherTest: Codable {
        let textual: String
    }
    
    let FEATURE_TOGGLE: Bool
    let AVOID_TOGGLES: Bool
    let integers: integersTest
    let decimals: decimalsTest
    let other: otherTest
}

class INICoderTests: XCTestCase {
    func testDecoder() throws {
        let raw = """
            FEATURE_TOGGLE = true
            AVOID_TOGGLES = off
            
            [integers]
            tiny_s = \(Int8.min)
            tiny_u = \(UInt8.max)
            small_s = \(Int16.min)
            small_u = \(UInt16.max)
            large_s = \(Int32.min)
            large_u = \(UInt32.max)
            huge_s = \(Int64.min)
            huge_u = \(UInt64.max)
            
            [decimals]
            small = \(Float.greatestFiniteMagnitude.significand)
            large = \(Double.greatestFiniteMagnitude.significand)
            
            [other]
            textual = "I am quite a bit of complicated text ❗️"
            """.data(using: .utf8)!
        
        do {
            let t = try INIDecoder(omitEmptyValues: true).decode(INITest.self, from: raw)
        
            XCTAssertEqual(t.FEATURE_TOGGLE, true)
            XCTAssertEqual(t.AVOID_TOGGLES, false)
            XCTAssertEqual(t.integers.tiny_s, Int8.min)
            XCTAssertEqual(t.integers.tiny_u, UInt8.max)
            XCTAssertEqual(t.integers.small_s, Int16.min)
            XCTAssertEqual(t.integers.small_u, UInt16.max)
            XCTAssertEqual(t.integers.large_s, Int32.min)
            XCTAssertEqual(t.integers.large_u, UInt32.max)
            XCTAssertEqual(t.integers.huge_s, Int64.min)
            XCTAssertEqual(t.integers.huge_u, UInt64.max)
            XCTAssertEqual(t.decimals.small, Float.greatestFiniteMagnitude.significand, accuracy: 1.0)
            XCTAssertEqual(t.decimals.large, Double.greatestFiniteMagnitude.significand, accuracy: 1.0)
            XCTAssertEqual(t.other.textual, "I am quite a bit of complicated text ❗️")
        } catch {
            // Because what XCTest prints for decoder errors is really really useless
            print(error)
            throw error
        }
    }

    static var allTests = [
        ("testDecoder", testDecoder)
    ]
}
