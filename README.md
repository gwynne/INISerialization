# INISerialization

A package which supports both deserialization and serialization of the INI file format. Some basic syntax options Are supported, including quoted string values, integer and boolean values, sections, and empty values. Most of these syntax options are configurable. In the default configuration, the deserializer will recognize only a very limited syntax. In the current version, the serializer is not configurable.

## Reading INI data

The API is designed to be similar to that of `JSONSerialization`:

```swift
let obj = INISerialization.iniObject(with: data)
```

The data encoding can be optionally specified; if it is not, a limited attempt is made to autodetect Unicode encodings. The `options:` parameter can be used to set any one of several options:

- `.detectNumericValues`: Integer and decimal values will be detected and returned as `Int` and `Double` types instead of strings.
- `.detectSections`: The `[section]` syntax will be supported, with a section being returned as a nested dictionary.
- `.allowHashComments`: By default the parser accepts only comments beginning with `;`. This option makes `#` a valid comment character as well.
- `.allowTrailingComments`: By default the parser accepts comments only when they appear on their own lines. This option allows comments to appear after any other valid syntactic construct on a line. However, beware using comments after values, as the results may be ambiguous.
- `.uppercaseKeys` and `.lowercaseKeys`: If set, these options cause all keys, including section names, to be normalized to uppercase or lowercase, respectively. If both are set, lowercase always wins.
- `.detectBooleanValues`: The Boolean names "on", "off", "yes", "no", "true", and "false" will be detected when they appear as the sole content of a value and returned as `Bool` types instead of strings.
- `.allowMissingValues`: Extends the syntax so a key which appears alone on a line with no `=` separator is treated as having an empty value instead of as a syntax error.
- `.allowSectionReset`: Extends the section syntax so the section header `[]` resets the current section to the "top" level. Has no effect if `.detectSection` is not also set.

## Writing INI data

Again, the API is designed to be familiar to `JSONSerialization` users:

```swift
let data = INISerialization.data(withIniObject: object)
```

The destination encoding of the data can be optionally specified; the default is UTF-8. While there is an optional `options` parameter, there are currently no options defined for serialization to data.

Using the public API, the ordering of keys in the output is undefined, except that top-level keys will always appear before any section headings regardless of the order in which Swift's dictionary implementation presents them. In the future, the internally available API for explicit ordering of keys may be made externally visible; this was not done for the current implementation because in its current form the ordered keys API is very unwieldy and the semantics are not intuitive.

## `Encoder` and `Decoder`

An implementation of `Decoder` as `INIDecoder` is provided. Errors are thrown if an attempt is made to decode an array, or a dictionary nested more than one level deep, as the INI syntax supported by this package does not support these structures.

An implementation of `Encoder` as `INIEncoder` is also provided. Due to limitations of the `Codable` protocol, a fatal error occurs if an attempt is made to encode an array. As with the decoder, an error is thrown if an attempt is made to nest a dictionary more than one level deep.

A simple example:

```swift
struct SomeData: Codable {
    struct Subsection: Codable {
        let first_subkey: Bool
        let second_subkey: Double?
    }
    let a_key: String
    let b_key: Int?
    let some_section: Subsection
}

let sampleObject = SomeData(
    a_key: "hello there",
    b_key: -5,
    some_section: .init(
        first_subkey: false,
        second_subkey: 1.25
    )
)

let data = INIEncoder().encode(sampleObject)

print(String(data: data, encoding: .utf8)!)
/*
a_key = "hello there"
b_key = -5
[some_section]
first_subkey = false
second_subkey = 1.25
*/

let decodedSampleObject = INIDecoder().decode(SomeData.self, from: data)

print(decodedSampleObject)
/*
SomeData(
    a_key: "hello there",
    b_key: Optional(-5),
    some_section: main.SomeData.Subsection(
        first_subkey: false,
        second_subkey: Optional(1.25)
    )
)
*/
```
