import Foundation
import CoreFoundation

enum JSONEntryKind: String, CaseIterable, Identifiable {
    case string
    case number
    case bool
    case null
    case array
    case object

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum JSONDocument {
    enum ValidationError: LocalizedError, Equatable {
        case invalidNumber(String)
        case invalidProfileName

        var errorDescription: String? {
            switch self {
            case .invalidNumber(let value):
                return "‘\(value)’ is not a valid JSON number."
            case .invalidProfileName:
                return "Profile name must contain at least one letter or number."
            }
        }
    }

    static func parseObject(_ text: String) throws -> [String: Any] {
        let normalized = normalizeQuotes(text)
        let value = try JSONSerialization.jsonObject(with: Data(normalized.utf8))
        guard let object = value as? [String: Any] else {
            throw CocoaError(.propertyListReadCorrupt)
        }
        return object
    }

    static func formattedText(from text: String) throws -> String {
        try formattedText(from: parseObject(text))
    }

    static func formattedText(from object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(
            withJSONObject: normalizedValue(object),
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        return String(decoding: data, as: UTF8.self) + "\n"
    }

    static func kind(for value: Any) -> JSONEntryKind {
        if value is NSNull { return .null }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? .bool : .number
        }
        if value is [Any] { return .array }
        if value is [String: Any] { return .object }
        return .string
    }

    static func value(for kind: JSONEntryKind, raw: String = "", boolValue: Bool = false) throws -> Any {
        let normalized = normalizeQuotes(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .string:
            return normalizeQuotes(raw)
        case .number:
            if let integer = Int64(normalized) { return integer }
            guard let number = Double(normalized), number.isFinite else {
                throw ValidationError.invalidNumber(raw)
            }
            return number
        case .bool:
            return boolValue
        case .null:
            return NSNull()
        case .array:
            return [Any]()
        case .object:
            return [String: Any]()
        }
    }

    static func value(at path: [String], in root: [String: Any]) -> Any? {
        var current: Any = root
        for component in path {
            guard let object = current as? [String: Any], let next = object[component] else {
                return nil
            }
            current = next
        }
        return current
    }

    static func setValue(_ value: Any, at path: [String], in root: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            root[first] = normalizedValue(value)
            return
        }
        var nested = root[first] as? [String: Any] ?? [:]
        setValue(value, at: Array(path.dropFirst()), in: &nested)
        root[first] = nested
    }

    static func removeValue(at path: [String], in root: inout [String: Any]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            root.removeValue(forKey: first)
            return
        }
        guard var nested = root[first] as? [String: Any] else { return }
        removeValue(at: Array(path.dropFirst()), in: &nested)
        root[first] = nested
    }

    static func sanitizeProfileName(_ value: String) -> String {
        let sanitized = value.trimmingCharacters(in: .whitespacesAndNewlines).map { character in
            (character.isLetter || character.isNumber || character == "-" || character == "_" || character == ".")
                ? character
                : "-"
        }.reduce(into: "") { result, character in
            if character != "-" || result.last != "-" {
                result.append(character)
            }
        }
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    static func validatedProfileName(_ value: String) throws -> String {
        let name = sanitizeProfileName(value)
        guard name.contains(where: { $0.isLetter || $0.isNumber }) else {
            throw ValidationError.invalidProfileName
        }
        return name
    }

    static func filteredNumberInput(_ value: String) -> String {
        var result = ""
        var hasDecimalSeparator = false

        for character in value {
            if character >= "0" && character <= "9" {
                result.append(character)
                continue
            }

            if character == "-", result.isEmpty {
                result.append(character)
                continue
            }

            if character == ".", !hasDecimalSeparator {
                hasDecimalSeparator = true
                result.append(character)
            }
        }

        return result
    }

    static func isPotentialNumberInput(_ value: String) -> Bool {
        guard !value.isEmpty else { return true }
        guard value == filteredNumberInput(value) else { return false }
        guard value.filter({ $0 == "-" }).count <= 1,
              value.filter({ $0 == "." }).count <= 1 else {
            return false
        }
        return value == "-" || value == "." || value == "-." || Double(value) != nil
    }

    static func normalizeQuotes(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x201C, 0x201D, 0x201E, 0x201F, 0x00AB, 0x00BB, 0xFF02:
                result.append("\"")
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }

    static func normalizedValue(_ value: Any) -> Any {
        if let string = value as? String { return normalizeQuotes(string) }
        if let array = value as? [Any] { return array.map(normalizedValue) }
        if let object = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: object.map { ($0.key, normalizedValue($0.value)) })
        }
        return value
    }
}
