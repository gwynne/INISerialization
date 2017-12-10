# INISerialization

A package which supports the "deserialization" (e.g. parsing) of the INI file format. Some basic syntax options Are supported, including quoted string values, integer and boolean values, sections, and empty values. Most of these syntax options are configurable. In the default configuration, the deserializer will recognize only a very limited syntax.

## Usage

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

## Decoder

An implementation of `Decoder` as `INIDecoder` is provided. Errors are thrown if an attempt is made to decode an array, or a dictionary nested more than one level deep, as the INI syntax supported by this package does not support these structures.
