import SwiftUI
import Foundation

enum JSONEntryKind: String, CaseIterable, Identifiable {
    case string
    case bool
    case array
    case object

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

struct JSONEntry: Identifiable {
    let id: String
    let path: [String]
    let key: String
    let kind: JSONEntryKind
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
    @State private var arrayItemKind: JSONEntryKind = .string
    @State private var arrayItemValue = ""
    @State private var arrayItemBoolValue = false

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
                .onChange(of: selectedEntryID) { _, _ in
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

                newValueEditor(kind: newKind)

                Button(addFieldButtonTitle) { addField() }
                    .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        case .bool, .string:
            return "Add Field"
        }
    }

    private var addChildButtonTitle: String {
        switch newKind {
        case .array:
            return "Create Array"
        case .object:
            return "Create Object"
        case .bool, .string:
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
        }
    }

    @ViewBuilder
    private func arrayNewValueEditor(kind: JSONEntryKind) -> some View {
        switch kind {
        case .bool:
            Toggle("", isOn: $arrayItemBoolValue)
                .toggleStyle(.checkbox)
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
            TextField("value", text: $arrayItemValue)
                .textFieldStyle(.roundedBorder)
        }
    }

    private func newValueForArrayItemKind(_ kind: JSONEntryKind) -> Any {
        switch kind {
        case .string:
            return normalizeQuotes(arrayItemValue)
        case .bool:
            return arrayItemBoolValue
        case .array:
            return [Any]()
        case .object:
            return [String: Any]()
        }
    }

    private func newValueForSelectedKind(_ kind: JSONEntryKind) -> Any {
        switch kind {
        case .string:
            return normalizeQuotes(newValue)
        case .bool:
            return newBoolValue
        case .array:
            return [Any]()
        case .object:
            return [String: Any]()
        }
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
                case .string:
                    TextField("value", text: Binding(
                        get: { currentText(at: entry.path) },
                        set: { setValue(at: entry.path, to: $0) }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
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

                    HStack(spacing: 8) {
                        TextField("new key", text: $newKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                        Picker("", selection: $newKind) {
                            ForEach(JSONEntryKind.allCases) { kind in
                                Text(kind.title).tag(kind)
                            }
                        }
                        .frame(width: 140)
                        newValueEditor(kind: newKind)
                        Button(addChildButtonTitle) { addField(parentPath: entry.path) }
                            .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        case .string:
            TextField("value", text: Binding(
                get: { currentArrayItemText(at: path, index: index) },
                set: { setArrayItemValue(at: path, index: index, value: $0) }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
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

            HStack(spacing: 8) {
                Picker("", selection: $arrayItemKind) {
                    ForEach(JSONEntryKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .frame(width: 120)

                arrayNewValueEditor(kind: arrayItemKind)

                Button("Add Array Item") {
                    addArrayValue(at: entry.path, kind: arrayItemKind, raw: arrayItemValue)
                    arrayItemValue = ""
                    arrayItemBoolValue = false
                }
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
                    case .string:
                        TextField("value", text: Binding(
                            get: { currentText(at: entry.path) },
                            set: { setValue(at: entry.path, to: $0) }
                        ))
                        .font(.system(.body, design: .monospaced))
                        .textFieldStyle(.roundedBorder)
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

                        HStack(spacing: 8) {
                            TextField("new key", text: $newKey)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 220)

                            Picker("", selection: $newKind) {
                                ForEach(JSONEntryKind.allCases) { kind in
                                    Text(kind.title).tag(kind)
                                }
                            }
                            .frame(width: 140)

                            newValueEditor(kind: newKind)

                            Button(addChildButtonTitle) { addField(parentPath: entry.path) }
                                .disabled(newKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
            let normalizedText = normalizeQuotes(jsonText)
            let object = try JSONSerialization.jsonObject(with: Data(normalizedText.utf8))
            errorText = nil
            return object as? [String: Any]
        } catch {
            errorText = "Invalid JSON: \(error.localizedDescription)"
            return nil
        }
    }

    private func kind(for value: Any) -> JSONEntryKind {
        if value is Bool { return .bool }
        if value is [Any] { return .array }
        if value is [String: Any] { return .object }
        return .string
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

    private func currentArrayValues(at path: [String]) -> [String] {
        currentArrayRawValues(at: path).map { normalizeQuotes(String(describing: $0)) }
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

    private func setArrayValue(at path: [String], index: Int, value: String) {
        setArrayItemValue(at: path, index: index, value: value)
    }

    private func setArrayItemValue(at path: [String], index: Int, value: Any) {
        var values = currentArrayRawValues(at: path)
        guard values.indices.contains(index) else { return }
        values[index] = normalizedValue(value)
        setValue(at: path, to: values)
    }

    private func addArrayValue(at path: [String], kind: JSONEntryKind = .string, raw: String = "") {
        var values = currentArrayRawValues(at: path)
        values.append(newValueForArrayItemKind(kind))
        setValue(at: path, to: values)
    }

    private func removeArrayValue(at path: [String], index: Int) {
        var values = currentArrayRawValues(at: path)
        guard values.indices.contains(index) else { return }
        values.remove(at: index)
        setValue(at: path, to: values)
    }

    private func setObjectText(at path: [String], text: String) {
        let fixedText = normalizeQuotes(text)
        if let data = fixedText.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: data) {
            setValue(at: path, to: parsed)
        } else {
            setValue(at: path, to: fixedText)
        }
    }

    private func setValue(at path: [String], to value: Any) {
        guard var root = rootObject() else { return }
        setValueInObject(&root, path: path, value: normalizedValue(value))
        write(root)
    }

    private func setValueInObject(_ object: inout [String: Any], path: [String], value: Any) {
        guard let first = path.first else { return }
        if path.count == 1 {
            object[first] = value
            return
        }
        var nested = object[first] as? [String: Any] ?? [:]
        setValueInObject(&nested, path: Array(path.dropFirst()), value: value)
        object[first] = nested
    }

    private func removeValue(at path: [String]) {
        guard var root = rootObject() else { return }
        removeValueFromObject(&root, path: path)
        write(root)
    }

    private func removeValueFromObject(_ object: inout [String: Any], path: [String]) {
        guard let first = path.first else { return }
        if path.count == 1 {
            object.removeValue(forKey: first)
            return
        }
        var nested = object[first] as? [String: Any] ?? [:]
        removeValueFromObject(&nested, path: Array(path.dropFirst()))
        object[first] = nested
    }

    private func addField(parentPath: [String]? = nil) {
        let key = normalizeQuotes(newKey.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !key.isEmpty, var root = rootObject() else { return }
        let value = newValueForSelectedKind(newKind)

        if let parentPath {
            setValueInObject(&root, path: parentPath + [key], value: normalizedValue(value))
        } else if newParent.isEmpty {
            root[key] = normalizedValue(value)
        } else {
            setValueInObject(&root, path: [newParent, key], value: normalizedValue(value))
        }

        newKey = ""
        newValue = ""
        newBoolValue = false
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
        case .bool:
            return fixed.lowercased() == "true" || fixed == "1"
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

    private func normalizeQuotes(_ value: String) -> String {
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

    private func normalizedValue(_ value: Any) -> Any {
        if let string = value as? String { return normalizeQuotes(string) }
        if let array = value as? [Any] { return array.map { normalizedValue($0) } }
        if let dict = value as? [String: Any] {
            return Dictionary(uniqueKeysWithValues: dict.map { ($0.key, normalizedValue($0.value)) })
        }
        return value
    }

    private func write(_ object: [String: Any]) {
        do {
            let normalized = normalizedValue(object)
            let data = try JSONSerialization.data(withJSONObject: normalized, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            jsonText = String(decoding: data, as: UTF8.self) + "\n"
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
