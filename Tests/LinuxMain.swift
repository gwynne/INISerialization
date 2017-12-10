import XCTest
@testable import INISerializationTests

XCTMain([
    testCase(INIParserTests.allTests),
    testCase(INITokenizerTests.allTests),
    testCase(INICoderTests.allTests),
    testCase(INIWriterTests.allTests),
])
