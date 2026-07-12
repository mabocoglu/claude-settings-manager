import Testing
import Foundation
@testable import ClaudeSettingsManager

@Test func parsesAndFormatsAllSupportedKinds() throws {
    let input = #"{"text":"hello","number":42,"flag":true,"nothing":null,"items":[1],"nested":{}}"#
    let object = try JSONDocument.parseObject(input)

    #expect(JSONDocument.kind(for: object["text"]!) == .string)
    #expect(JSONDocument.kind(for: object["number"]!) == .number)
    #expect(JSONDocument.kind(for: object["flag"]!) == .bool)
    #expect(JSONDocument.kind(for: object["nothing"]!) == .null)
    #expect(JSONDocument.kind(for: object["items"]!) == .array)
    #expect(JSONDocument.kind(for: object["nested"]!) == .object)

    let formatted = try JSONDocument.formattedText(from: object)
    #expect(formatted.hasSuffix("\n"))
    #expect(formatted.contains("\"number\" : 42"))
}

@Test func mutatesNestedValues() {
    var root: [String: Any] = ["parent": ["old": true]]
    JSONDocument.setValue(12, at: ["parent", "count"], in: &root)
    #expect((JSONDocument.value(at: ["parent", "count"], in: root) as? Int) == 12)

    JSONDocument.removeValue(at: ["parent", "old"], in: &root)
    #expect(JSONDocument.value(at: ["parent", "old"], in: root) == nil)
}

@Test func normalizesQuotesAndSanitizesProfileNames() {
    #expect(JSONDocument.normalizeQuotes("“value”") == "\"value\"")
    #expect(JSONDocument.sanitizeProfileName("  work profile/1  ") == "work-profile-1")
    #expect(JSONDocument.sanitizeProfileName("work///profile") == "work-profile")
    #expect(JSONDocument.sanitizeProfileName("...").isEmpty)
}

@Test func createsNumberAndNullValues() throws {
    #expect((try JSONDocument.value(for: .number, raw: "42") as? Int64) == 42)
    #expect((try JSONDocument.value(for: .number, raw: "3.5") as? Double) == 3.5)
    #expect(try JSONDocument.value(for: .null) is NSNull)
}

@Test func rejectsInvalidNumbersAndProfileNames() {
    #expect(throws: JSONDocument.ValidationError.invalidNumber("abc")) {
        try JSONDocument.value(for: .number, raw: "abc")
    }
    #expect(throws: JSONDocument.ValidationError.invalidProfileName) {
        try JSONDocument.validatedProfileName("...")
    }
}

@Test func filtersNumberInputWhileTyping() {
    #expect(JSONDocument.filteredNumberInput("12abc.5") == "12.5")
    #expect(JSONDocument.filteredNumberInput("-3.14") == "-3.14")
    #expect(JSONDocument.filteredNumberInput("1e-4text") == "14")
    #expect(JSONDocument.filteredNumberInput("12E3") == "123")
    #expect(JSONDocument.filteredNumberInput("+42") == "42")
    #expect(JSONDocument.filteredNumberInput("abc").isEmpty)
}

@Test func rejectsTextBeforeNumberFieldMutation() {
    #expect(JSONDocument.isPotentialNumberInput(""))
    #expect(JSONDocument.isPotentialNumberInput("-"))
    #expect(JSONDocument.isPotentialNumberInput("-."))
    #expect(JSONDocument.isPotentialNumberInput("-12.5"))
    #expect(!JSONDocument.isPotentialNumberInput("a"))
    #expect(!JSONDocument.isPotentialNumberInput("12a"))
    #expect(!JSONDocument.isPotentialNumberInput("1.2.3"))
}

@Test func mutatesArbitrarilyNestedObjects() {
    var root: [String: Any] = [
        "level1": [
            "level2": [
                "level3": [String: Any]()
            ]
        ]
    ]

    JSONDocument.setValue(42, at: ["level1", "level2", "level3", "answer"], in: &root)
    #expect((JSONDocument.value(at: ["level1", "level2", "level3", "answer"], in: root) as? Int) == 42)
}

@MainActor
@Test func settingsStoreUsesInjectedDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try #"{"enabled":true}"#.write(
        to: directory.appendingPathComponent("settings.json"),
        atomically: true,
        encoding: .utf8
    )

    let store = SettingsStore(claudeDirectory: directory)
    #expect(store.profiles.count == 1)
    #expect(store.selected?.isActive == true)
    #expect(store.editorText.contains("\"enabled\" : true"))
}
