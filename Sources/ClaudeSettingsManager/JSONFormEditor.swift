import SwiftUI
import Foundation
import AppKit

struct JSONEntry: Identifiable {
    let id: String
    let path: [String]
    let key: String
    let kind: JSONEntryKind
}

private struct NumberTextField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onCommit: onCommit)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = "value"
        textField.isBezeled = true
        textField.bezelStyle = .roundedBezel
        textField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textField.formatter = NumericInputFormatter()
        textField.delegate = context.coordinator
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: Context) {
        context.coordinator.text = $text
        context.coordinator.onCommit = onCommit
        if textField.stringValue != text {
            textField.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var text: Binding<String>
        var onCommit: (() -> Void)?

        init(text: Binding<String>, onCommit: (() -> Void)?) {
            self.text = text
            self.onCommit = onCommit
        }

        @MainActor
        func control(
            _ control: NSControl,
            textView: NSTextView,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String?
        ) -> Bool {
            let currentValue = textView.string as NSString
            let candidate = currentValue.replacingCharacters(in: range, with: string ?? "")
            guard JSONDocument.isPotentialNumberInput(candidate) else { return false }
            text.wrappedValue = candidate
            return true
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let filteredValue = JSONDocument.filteredNumberInput(textField.stringValue)
            if textField.stringValue != filteredValue {
                textField.stringValue = filteredValue
                if let editor = textField.currentEditor() {
                    editor.selectedRange = NSRange(location: filteredValue.utf16.count, length: 0)
                }
            }
            text.wrappedValue = filteredValue
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            onCommit?()
        }
    }
}

private final class NumericInputFormatter: Formatter {
    override func string(for object: Any?) -> String? {
        object as? String
    }

    override func getObjectValue(
        _ object: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        guard JSONDocument.isPotentialNumberInput(string) else { return false }
        object?.pointee = string as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        JSONDocument.isPotentialNumberInput(partialStringPtr.pointee as String)
    }
}

private struct ScalarValueField: View {
    let value: String
    let kind: JSONEntryKind
    let onCommit: (String) -> Void

    @State private var draft: String
    @FocusState private var isFocused: Bool

    init(value: String, kind: JSONEntryKind, onCommit: @escaping (String) -> Void) {
        self.value = value
        self.kind = kind
        self.onCommit = onCommit
        _draft = State(initialValue: value)
    }

    var body: some View {
        Group {
            if kind == .number {
                NumberTextField(text: $draft, onCommit: commit)
            } else {
                TextField("value", text: $draft)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
            }
        }
            .focused($isFocused)
            .onSubmit { commit() }
            .onChange(of: isFocused) { focused in
                if !focused { commit() }
            }
            .onChange(of: value) { newValue in
                if !isFocused { draft = newValue }
            }
    }

    private func commit() {
        guard draft != value else { return }
        if kind == .number, Double(draft.trimmingCharacters(in: .whitespacesAndNewlines)) == nil {
            draft = value
            return
        }
        onCommit(draft)
    }
}

private struct ObjectChildFieldControls: View {
    let parentPath: [String]
    let onAdd: ([String], String, JSONEntryKind, String, Bool) -> Void

    @State private var key = ""
    @State private var kind: JSONEntryKind = .string
    @State private var value = ""
    @State private var boolValue = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("new key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 120, idealWidth: 220)

                Picker("", selection: $kind) {
                    ForEach(JSONEntryKind.allCases) { entryKind in
                        Text(entryKind.title).tag(entryKind)
                    }
                }
                .frame(width: 140)
                .onChange(of: kind) { newKind in
                    if newKind == .number {
                        value = JSONDocument.filteredNumberInput(value)
                    }
                }
            }

            HStack(spacing: 8) {
                valueEditor
                Button(buttonTitle) { addChild() }
                    .disabled(
                        key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (kind == .number && !isValidNumber)
                    )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buttonTitle: String {
        switch kind {
        case .array: return "Create Array"
        case .object: return "Create Object"
        case .bool, .string, .number, .null: return "Add Child"
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch kind {
        case .bool:
            Toggle("", isOn: $boolValue)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .null:
            Text("null")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .array:
            Label("Array group", systemImage: "list.bullet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .object:
            Label("Object group", systemImage: "curlybraces")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .string:
            TextField("value", text: $value)
                .textFieldStyle(.roundedBorder)
        case .number:
            NumberTextField(text: $value)
        }
    }

    private var isValidNumber: Bool {
        guard kind == .number else { return true }
        return (try? JSONDocument.value(for: .number, raw: value)) != nil
    }

    private func addChild() {
        let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else { return }
        onAdd(parentPath, trimmedKey, kind, value, boolValue)
        key = ""
        value = ""
        boolValue = false
    }
}

private struct ArrayItemControls: View {
    let arrayPath: [String]
    let onAdd: ([String], JSONEntryKind, String, Bool) -> Void

    @State private var kind: JSONEntryKind = .string
    @State private var value = ""
    @State private var boolValue = false

    var body: some View {
        HStack(spacing: 8) {
            Picker("", selection: $kind) {
                ForEach(JSONEntryKind.allCases) { entryKind in
                    Text(entryKind.title).tag(entryKind)
                }
            }
            .frame(width: 120)
            .onChange(of: kind) { newKind in
                if newKind == .number {
                    value = JSONDocument.filteredNumberInput(value)
                }
            }

            valueEditor

            Button("Add Array Item") {
                onAdd(arrayPath, kind, value, boolValue)
                value = ""
                boolValue = false
            }
        }
    }

    @ViewBuilder
    private var valueEditor: some View {
        switch kind {
        case .bool:
            Toggle("", isOn: $boolValue)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .null:
            Text("null")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .array:
            Label("Array", systemImage: "list.bullet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .object:
            Label("Object", systemImage: "curlybraces")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .string:
            TextField("value", text: $value)
                .textFieldStyle(.roundedBorder)
        case .number:
            NumberTextField(text: $value)
        }
    }

}

struct JSONFormEditor: View {
    @Binding var jsonText: String
    @State private var errorText: String?
    @State private var selectedEntryID = ""
    @State private var selectedKind: JSONEntryKind = .string
    @State private var newParent = ""
    @State private var newKey = ""
    @State private var newKind: JSONEntryKind = .string
    @State private var newValue = ""
    @State private var newBoolValue = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let errorText {
                    Text(errorText)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.red.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                ForEach(entries) { entry in
                    row(for: entry)
                }

                fieldControls
            }
            .padding(12)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
    }

    private var fieldControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Picker("Existing field", selection: $selectedEntryID) {
                    Text("Select field").tag("")
                    ForEach(entries) { entry in
                        Text(entry.key).tag(entry.id)
                    }
                }
                .frame(width: 260)
                .onChange(of: selectedEntryID) { _ in
                    if let selectedEntry { selectedKind = selectedEntry.kind }
                }

                Picker("Type", selection: $selectedKind) {
                    ForEach(JSONEntryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 150)

                Button("Apply Type") { updateSelectedFieldType() }
                    .disabled(selectedEntry == nil)
            }

            HStack(spacing: 8) {
                Picker("Parent", selection: $newParent) {
                    Text("root").tag("")
                    ForEach(objectParentKeys, id: \.self) { key in
                        Text(key).tag(key)
                    }
                }
                .frame(width: 150)

                TextField("new key", text: $newKey)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)

                Picker("Type", selection: $newKind) {
                    ForEach(JSONEntryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 140)
                .onChange(of: newKind) { kind in
                    if kind == .number {
                        newValue = JSONDocument.filteredNumberInput(newValue)
                    }
                }

                newValueEditor(kind: newKind)

                Button(addFieldButtonTitle) { addField() }
                    .disabled(
                        newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (newKind == .number && !isNewNumberValid)
                    )
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
    }

    private var addFieldButtonTitle: String {
        switch newKind {
        case .array:
            return "Create Array"
        case .object:
            return "Create Object"
        case .bool, .string, .number, .null:
            return "Add Field"
        }
    }

    private var isNewNumberValid: Bool {
        guard newKind == .number else { return true }
        return (try? JSONDocument.value(for: .number, raw: newValue)) != nil
    }

    private var addChildButtonTitle: String {
        switch newKind {
        case .array:
            return "Create Array"
        case .object:
            return "Create Object"
        case .bool, .string, .number, .null:
            return "Add Child"
        }
    }

    private var entries: [JSONEntry] {
        guard let root = rootObject() else { return [] }
        var result: [JSONEntry] = []

        for key in root.keys.sorted() {
            guard let value = root[key] else { continue }
            result.append(JSONEntry(id: key, path: [key], key: key, kind: kind(for: value)))
        }

        return result
    }

    private var selectedEntry: JSONEntry? {
        entries.first { $0.id == selectedEntryID }
    }

    private var objectParentKeys: [String] {
        guard let root = rootObject() else { return [] }
        return root.keys.sorted().filter { root[$0] is [String: Any] }
    }

    private func objectChildEntries(at path: [String]) -> [JSONEntry] {
        guard let object = currentValue(at: path) as? [String: Any] else { return [] }
        return object.keys.sorted().compactMap { key in
            guard let value = object[key] else { return nil }
            return JSONEntry(id: (path + [key]).joined(separator: "."), path: path + [key], key: key, kind: kind(for: value))
        }
    }

    @ViewBuilder
    private func newValueEditor(kind: JSONEntryKind) -> some View {
        switch kind {
        case .bool:
            Toggle("", isOn: $newBoolValue)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .null:
            Text("null")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .array:
            Label("Array group", systemImage: "list.bullet")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Creates an array. Add items from the array group after creating it.")
        case .object:
            Label("Object group", systemImage: "curlybraces")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help("Creates an object. Add key/value children from the object group after creating it.")
        case .string:
            TextField("value", text: $newValue)
                .textFieldStyle(.roundedBorder)
        case .number:
            NumberTextField(text: $newValue)
        }
    }

    private func newValueForSelectedKind(_ kind: JSONEntryKind) -> Any {
        (try? JSONDocument.value(for: kind, raw: newValue, boolValue: newBoolValue)) ?? newValue
    }

    @ViewBuilder
    private func row(for entry: JSONEntry) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(entry.key)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                    .frame(width: 260, alignment: .leading)
                    .lineLimit(3)
                    .textSelection(.enabled)

                Text(entry.kind.title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .leading)

                switch entry.kind {
                case .bool:
                    Toggle("", isOn: Binding(
                        get: { currentBool(at: entry.path) },
                        set: { setValue(at: entry.path, to: $0) }
                    ))
                    .toggleStyle(.checkbox)
                    .frame(maxWidth: .infinity, alignment: .leading)
                case .null:
                    Text("null")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .array:
                    Text("Array")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .object:
                    Text("Object")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                case .string, .number:
                    ScalarValueField(
                        value: currentText(at: entry.path),
                        kind: entry.kind
                    ) { text in
                        setValue(at: entry.path, to: parsedScalar(text, kind: entry.kind))
                    }
                }

                Button(role: .destructive) { removeValue(at: entry.path) } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }

            if entry.kind == .object {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(objectChildEntries(at: entry.path)) { child in
                        childRow(for: child)
                    }

                    ObjectChildFieldControls(parentPath: entry.path) { path, key, kind, value, boolValue in
                        addField(parentPath: path, key: key, kind: kind, rawValue: value, boolValue: boolValue)
                    }
                }
                .padding(.leading, 24)
            }

            if entry.kind == .array {
                arrayGroup(for: entry)
                    .padding(.leading, 270)
            }
        }
        .padding(10)
        .background(.thinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.18)))
    }

    @ViewBuilder
    private func arrayItemEditor(path: [String], index: Int, kind: JSONEntryKind) -> some View {
        switch kind {
        case .bool:
            Toggle("", isOn: Binding(
                get: { (currentArrayRawValues(at: path)[safe: index] as? Bool) ?? false },
                set: { setArrayItemValue(at: path, index: index, value: $0) }
            ))
            .toggleStyle(.checkbox)
            .frame(maxWidth: .infinity, alignment: .leading)
        case .null:
            Text("null")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .array:
            Text("Array")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .object:
            Text("Object")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .string, .number:
            ScalarValueField(
                value: currentArrayItemText(at: path, index: index),
                kind: kind
            ) { text in
                setArrayItemValue(at: path, index: index, value: parsedScalar(text, kind: kind))
            }
        }
    }

    private func arrayGroup(for entry: JSONEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(currentArrayRawValues(at: entry.path).indices, id: \.self) { index in
                let itemKind = currentArrayItemKind(at: entry.path, index: index)
                HStack(alignment: .top, spacing: 8) {
                    Text(itemKind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)

                    arrayItemEditor(path: entry.path, index: index, kind: itemKind)

                    Button(role: .destructive) { removeArrayValue(at: entry.path, index: index) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }
            }

            ArrayItemControls(arrayPath: entry.path) { path, kind, value, boolValue in
                addArrayValue(at: path, kind: kind, raw: value, boolValue: boolValue)
            }
        }
    }

    private func childRow(for entry: JSONEntry) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 10) {
                    Text(entry.key)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.primary)
                        .frame(width: 220, alignment: .leading)
                        .lineLimit(2)
                        .textSelection(.enabled)

                    Text(entry.kind.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)

                    switch entry.kind {
                    case .bool:
                        Toggle("", isOn: Binding(
                            get: { currentBool(at: entry.path) },
                            set: { setValue(at: entry.path, to: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .null:
                        Text("null")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .array:
                        Text("Array")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .object:
                        Text("Object")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    case .string, .number:
                        ScalarValueField(
                            value: currentText(at: entry.path),
                            kind: entry.kind
                        ) { text in
                            setValue(at: entry.path, to: parsedScalar(text, kind: entry.kind))
                        }
                    }

                    Button(role: .destructive) { removeValue(at: entry.path) } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Delete")
                }

                if entry.kind == .object {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(objectChildEntries(at: entry.path)) { child in
                            childRow(for: child)
                        }

                        ObjectChildFieldControls(parentPath: entry.path) { path, key, kind, value, boolValue in
                            addField(parentPath: path, key: key, kind: kind, rawValue: value, boolValue: boolValue)
                        }
                    }
                    .padding(.leading, 24)
                }

                if entry.kind == .array {
                    arrayGroup(for: entry)
                        .padding(.leading, 24)
                }
            }
            .padding(8)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.14)))
        )
    }

    private func rootObject() -> [String: Any]? {
        do {
            let object = try JSONDocument.parseObject(jsonText)
            errorText = nil
            return object
        } catch {
            errorText = "Invalid JSON: \(error.localizedDescription)"
            return nil
        }
    }

    private func kind(for value: Any) -> JSONEntryKind {
        JSONDocument.kind(for: value)
    }

    private func currentValue(at path: [String]) -> Any? {
        guard let root = rootObject() else { return nil }
        var value: Any? = root
        for key in path {
            value = (value as? [String: Any])?[key]
        }
        return value
    }

    private func currentText(at path: [String]) -> String {
        guard let value = currentValue(at: path) else { return "" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: normalizedValue(value), options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
            return normalizeQuotes(String(decoding: data, as: UTF8.self))
        }
        return normalizeQuotes(String(describing: value))
    }

    private func currentBool(at path: [String]) -> Bool {
        currentValue(at: path) as? Bool ?? false
    }

    private func currentArrayRawValues(at path: [String]) -> [Any] {
        currentValue(at: path) as? [Any] ?? []
    }

    private func currentArrayItemKind(at path: [String], index: Int) -> JSONEntryKind {
        guard let value = currentArrayRawValues(at: path)[safe: index] else { return .string }
        return kind(for: value)
    }

    private func currentArrayItemText(at path: [String], index: Int) -> String {
        guard let value = currentArrayRawValues(at: path)[safe: index] else { return "" }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: normalizedValue(value), options: [.sortedKeys, .withoutEscapingSlashes]) {
            return normalizeQuotes(String(decoding: data, as: UTF8.self))
        }
        return normalizeQuotes(String(describing: value))
    }

    private func setArrayItemValue(at path: [String], index: Int, value: Any) {
        var values = currentArrayRawValues(at: path)
        guard values.indices.contains(index) else { return }
        values[index] = normalizedValue(value)
        setValue(at: path, to: values)
    }

    private func addArrayValue(
        at path: [String],
        kind: JSONEntryKind = .string,
        raw: String = "",
        boolValue: Bool = false
    ) {
        var values = currentArrayRawValues(at: path)
        guard let value = try? JSONDocument.value(for: kind, raw: raw, boolValue: boolValue) else { return }
        values.append(value)
        setValue(at: path, to: values)
    }

    private func removeArrayValue(at path: [String], index: Int) {
        var values = currentArrayRawValues(at: path)
        guard values.indices.contains(index) else { return }
        values.remove(at: index)
        setValue(at: path, to: values)
    }

    private func setValue(at path: [String], to value: Any) {
        guard var root = rootObject() else { return }
        JSONDocument.setValue(value, at: path, in: &root)
        write(root)
    }

    private func removeValue(at path: [String]) {
        guard var root = rootObject() else { return }
        JSONDocument.removeValue(at: path, in: &root)
        write(root)
    }

    private func addField(parentPath: [String]? = nil) {
        addField(
            parentPath: parentPath,
            key: newKey,
            kind: newKind,
            rawValue: newValue,
            boolValue: newBoolValue
        )
        newKey = ""
        newValue = ""
        newBoolValue = false
    }

    private func addField(
        parentPath: [String]?,
        key rawKey: String,
        kind: JSONEntryKind,
        rawValue: String,
        boolValue: Bool
    ) {
        let key = normalizeQuotes(rawKey.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty, var root = rootObject() else { return }
        guard let value = try? JSONDocument.value(for: kind, raw: rawValue, boolValue: boolValue) else { return }

        if let parentPath {
            JSONDocument.setValue(value, at: parentPath + [key], in: &root)
        } else if newParent.isEmpty {
            root[key] = normalizedValue(value)
        } else {
            JSONDocument.setValue(value, at: [newParent, key], in: &root)
        }

        write(root)
    }

    private func updateSelectedFieldType() {
        guard let entry = selectedEntry else { return }
        setValue(at: entry.path, to: defaultValue(for: selectedKind, raw: currentText(at: entry.path)))
    }

    private func defaultValue(for kind: JSONEntryKind, raw: String) -> Any {
        let fixed = normalizeQuotes(raw)
        switch kind {
        case .string:
            return fixed
        case .number:
            return (try? JSONDocument.value(for: .number, raw: fixed)) ?? currentValue
        case .bool:
            return fixed.lowercased() == "true" || fixed == "1"
        case .null:
            return NSNull()
        case .array:
            return fixed.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        case .object:
            if let data = fixed.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data),
               parsed is [String: Any] {
                return parsed
            }
            return [String: Any]()
        }
    }

    private func parsedScalar(_ text: String, kind: JSONEntryKind) -> Any {
        (try? JSONDocument.value(for: kind, raw: text)) ?? text
    }

    private func normalizeQuotes(_ value: String) -> String {
        JSONDocument.normalizeQuotes(value)
    }

    private func normalizedValue(_ value: Any) -> Any {
        JSONDocument.normalizedValue(value)
    }

    private func write(_ object: [String: Any]) {
        do {
            jsonText = try JSONDocument.formattedText(from: object)
            errorText = nil
        } catch {
            errorText = "Could not build JSON: \(error.localizedDescription)"
        }
    }
}

private extension Array {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
