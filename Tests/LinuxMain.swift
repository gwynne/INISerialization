import XCTest
@testable import INISerializationTests

XCTMain([
    testCase(INISerializationTests.allTests),
    testCase(INITokenizerTests.allTests),
    testCase(INICoderTests.allTests),
    testCase(INIWriterTests.allTests),
])
