import FolioFoldCore
import SwiftUI

struct TemplateWorkspace: View {
    @Binding var editor: FolioEditor
    let isReadOnly: Bool
    let report: (String) -> Void

    @State private var isPresented = false
    @State private var fieldName = ""
    @State private var fieldKind: TemplateField.Kind = .text
    @State private var fieldFormat = ""
    @State private var fieldDefault = ""
    @State private var values: [UUID: String] = [:]
    @State private var sequenceNumber = 1

    var body: some View {
        Button("Templates…", systemImage: "doc.text.magnifyingglass") {
            isPresented = true
        }
        .disabled(isReadOnly)
        .accessibilityIdentifier("folio.templates")
        .sheet(isPresented: $isPresented) {
            NavigationStack {
                Form {
                    Section("Template Fields") {
                        if editor.document.templateFields.isEmpty {
                            Text("Add a field, then bind it to a block to create a reusable template.")
                                .foregroundStyle(.secondary)
                        }
                        ForEach(editor.document.templateFields) { field in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Label(field.name, systemImage: field.kind.systemImage)
                                    Spacer()
                                    Text(field.kind.displayName)
                                        .foregroundStyle(.secondary)
                                    Button(role: .destructive) { remove(field) } label: {
                                        Label("Delete Template Field", systemImage: "trash")
                                    }
                                    .labelStyle(.iconOnly)
                                }
                                if field.kind != .sequence && field.kind != .tableRow {
                                    TextField("Generated value", text: valueBinding(for: field.id))
                                }
                            }
                        }
                    }

                    Section("Add Template Field") {
                        TextField("Field name", text: $fieldName)
                        Picker("Field type", selection: $fieldKind) {
                            Text("Text").tag(TemplateField.Kind.text)
                            Text("Date").tag(TemplateField.Kind.date)
                            Text("Number").tag(TemplateField.Kind.number)
                            Text("Currency").tag(TemplateField.Kind.currency)
                            Text("Sequence").tag(TemplateField.Kind.sequence)
                            Text("Repeatable Table Row").tag(TemplateField.Kind.tableRow)
                        }
                        TextField("Format", text: $fieldFormat)
                        TextField("Default value", text: $fieldDefault)
                        Button("Add Template Field") { addField() }
                            .disabled(fieldName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }

                    Section("Block Bindings") {
                        ForEach(editor.document.flow) { block in
                            Menu {
                                Button("No Template Field") {
                                    bind(blockID: block.id, to: nil)
                                }
                                ForEach(editor.document.templateFields) { field in
                                    Button(field.name) {
                                        bind(blockID: block.id, to: field.id)
                                    }
                                }
                            } label: {
                                LabeledContent(
                                    blockKindName(block.kind),
                                    value: boundFieldName(for: block)
                                )
                            }
                        }
                    }

                    Section("Generate Document") {
                        Stepper("Sequence number: (sequenceNumber)", value: $sequenceNumber, in: 1...999999)
                        Text("Date, number, and currency values use the current locale. Repeatable table rows remain structured template data in the FolioFold document.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Generate from Template") { generate() }
                            .disabled(editor.document.templateFields.isEmpty)
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Template")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { isPresented = false }
                    }
                }
                .frame(minWidth: 560, minHeight: 520)
            }
        }
    }

    private func valueBinding(for fieldID: UUID) -> Binding<String> {
        Binding(
            get: { values[fieldID, default: ""] },
            set: { values[fieldID] = $0 }
        )
    }

    private func bind(blockID: UUID, to fieldID: UUID?) {
        do {
            try editor.bind(blockID: blockID, to: fieldID)
        } catch {
            report(error.localizedDescription)
        }
    }

    private func boundFieldName(for block: Block) -> String {
        guard let fieldID = block.templateFieldID,
              let field = editor.document.templateFields.first(where: { $0.id == fieldID }) else {
            return "No Template Field"
        }
        return field.name
    }

    private func blockKindName(_ kind: Block.Kind) -> String {
        switch kind {
        case .paragraph: "Text"
        case .heading: "Heading"
        case .list: "List"
        case .table: "Table"
        case .image: "Image"
        case .divider: "Divider"
        case .shape: "Shape"
        case .formField: "Form Field"
        case .signatureField: "Signature Field"
        case .pageBreak: "Page Break"
        }
    }

    private func addField() {
        let field = TemplateField(
            name: fieldName.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: fieldKind,
            format: fieldFormat.isEmpty ? nil : fieldFormat,
            defaultValue: fieldDefault.isEmpty ? nil : fieldDefault
        )
        do {
            try editor.setTemplateFields(editor.document.templateFields + [field])
            fieldName = ""
            fieldFormat = ""
            fieldDefault = ""
        } catch {
            report(error.localizedDescription)
        }
    }

    private func remove(_ field: TemplateField) {
        do {
            try editor.setTemplateFields(editor.document.templateFields.filter { $0.id != field.id })
            values[field.id] = nil
        } catch {
            report(error.localizedDescription)
        }
    }

    private func generate() {
        do {
            var renderedValues: [UUID: TemplateValue] = [:]
            for field in editor.document.templateFields {
                guard let raw = values[field.id], !raw.isEmpty else { continue }
                switch field.kind {
                case .text:
                    renderedValues[field.id] = .text(raw)
                case .date:
                    guard let value = DateFormatter.templateInput.date(from: raw) else {
                        throw TemplateWorkspaceError.invalidValue(field.name)
                    }
                    renderedValues[field.id] = .date(value)
                case .number, .currency:
                    guard let value = Decimal(string: raw, locale: .current) else {
                        throw TemplateWorkspaceError.invalidValue(field.name)
                    }
                    renderedValues[field.id] = .number(value)
                case .sequence, .tableRow:
                    break
                }
            }
            try editor.applyTemplateValues(renderedValues, sequenceNumber: sequenceNumber)
            report("Generated document from template.")
            isPresented = false
        } catch {
            report(error.localizedDescription)
        }
    }
}

private enum TemplateWorkspaceError: LocalizedError {
    case invalidValue(String)

    var errorDescription: String? {
        switch self {
        case .invalidValue(let field):
            "Enter a valid value for " + field + "."
        }
    }
}

private extension DateFormatter {
    static let templateInput: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter
    }()
}

private extension TemplateField.Kind {
    static var allCases: [Self] { [.text, .date, .number, .currency, .sequence, .tableRow] }

    var displayName: String {
        switch self {
        case .text: "Text"
        case .date: "Date"
        case .number: "Number"
        case .currency: "Currency"
        case .sequence: "Sequence"
        case .tableRow: "Repeatable Table Row"
        }
    }

    var systemImage: String {
        switch self {
        case .text: "textformat"
        case .date: "calendar"
        case .number: "number"
        case .currency: "dollarsign.circle"
        case .sequence: "number.square"
        case .tableRow: "tablecells"
        }
    }
}
