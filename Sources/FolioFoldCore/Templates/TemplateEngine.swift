import Foundation

public enum TemplateValue: Equatable, Sendable {
    case text(String)
    case date(Date)
    case number(Decimal)
    case rows([[String: TemplateValue]])
}

public enum TemplateFormula: Equatable, Sendable {
    case subtotal([Decimal])
    case percentage(base: Decimal, rate: Decimal)
    case sum([Decimal])
    case grandTotal(subtotal: Decimal, additions: [Decimal])
}

public enum TemplateEngineError: Error, Equatable, Sendable {
    case duplicateFieldName(String)
    case invalidValue(field: String)
    case invalidSequenceFormat(String)
    case unknownField(UUID)
}

public struct TemplateRenderResult: Equatable, Sendable {
    public var document: FolioDocument
    public var renderedValues: [UUID: String]
    public var tableRows: [UUID: [[String: TemplateValue]]]

    public init(
        document: FolioDocument,
        renderedValues: [UUID: String],
        tableRows: [UUID: [[String: TemplateValue]]]
    ) {
        self.document = document
        self.renderedValues = renderedValues
        self.tableRows = tableRows
    }
}

public struct TemplateEngine: Sendable {
    public var locale: Locale
    public var timeZone: TimeZone

    public init(locale: Locale = .current, timeZone: TimeZone = .current) {
        self.locale = locale
        self.timeZone = timeZone
    }

    public func render(
        document: FolioDocument,
        values: [UUID: TemplateValue] = [:],
        sequenceNumber: Int = 1
    ) throws -> TemplateRenderResult {
        var names = Set<String>()
        for field in document.templateFields {
            let key = field.name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: locale)
            guard names.insert(key).inserted else {
                throw TemplateEngineError.duplicateFieldName(field.name)
            }
        }

        var rendered: [UUID: String] = [:]
        var rows: [UUID: [[String: TemplateValue]]] = [:]
        for field in document.templateFields {
            let value = values[field.id]
            if field.kind == .tableRow {
                if case .rows(let suppliedRows) = value {
                    rows[field.id] = suppliedRows
                } else if value != nil {
                    throw TemplateEngineError.invalidValue(field: field.name)
                } else {
                    rows[field.id] = []
                }
                continue
            }
            rendered[field.id] = try renderValue(
                value,
                field: field,
                sequenceNumber: sequenceNumber
            )
        }

        var output = document
        output.flow = try output.flow.map { block in
            guard let fieldID = block.templateFieldID else { return block }
            guard output.templateFields.contains(where: { $0.id == fieldID }) else {
                throw TemplateEngineError.unknownField(fieldID)
            }
            var copy = block
            if let value = rendered[fieldID] { copy.text = value }
            return copy
        }
        return TemplateRenderResult(document: output, renderedValues: rendered, tableRows: rows)
    }

    public func evaluate(_ formula: TemplateFormula) -> Decimal {
        switch formula {
        case .subtotal(let values), .sum(let values):
            return values.reduce(0, +)
        case .percentage(let base, let rate):
            return base * rate / 100
        case .grandTotal(let subtotal, let additions):
            return subtotal + additions.reduce(0, +)
        }
    }

    private func renderValue(
        _ supplied: TemplateValue?,
        field: TemplateField,
        sequenceNumber: Int
    ) throws -> String {
        switch field.kind {
        case .text:
            if case .text(let value) = supplied { return value }
            if supplied == nil { return field.defaultValue ?? "" }
        case .date:
            if case .date(let value) = supplied {
                let formatter = DateFormatter()
                formatter.locale = locale
                formatter.timeZone = timeZone
                if let format = field.format, !format.isEmpty {
                    formatter.dateFormat = format
                } else {
                    formatter.dateStyle = .medium
                    formatter.timeStyle = .none
                }
                return formatter.string(from: value)
            }
            if supplied == nil { return field.defaultValue ?? "" }
        case .number:
            if case .number(let value) = supplied {
                return numberFormatter(style: .decimal, format: field.format).string(from: value as NSDecimalNumber) ?? ""
            }
            if supplied == nil { return field.defaultValue ?? "" }
        case .currency:
            if case .number(let value) = supplied {
                return numberFormatter(style: .currency, format: field.format).string(from: value as NSDecimalNumber) ?? ""
            }
            if supplied == nil { return field.defaultValue ?? "" }
        case .sequence:
            guard supplied == nil else { throw TemplateEngineError.invalidValue(field: field.name) }
            let format = field.format ?? "%d"
            guard isSafeSequenceFormat(format) else {
                throw TemplateEngineError.invalidSequenceFormat(format)
            }
            return String(format: format, locale: locale, sequenceNumber)
        case .tableRow:
            return ""
        }
        throw TemplateEngineError.invalidValue(field: field.name)
    }

    private func numberFormatter(style: NumberFormatter.Style, format: String?) -> NumberFormatter {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = style
        if style == .currency, let code = format, code.count == 3 {
            formatter.currencyCode = code.uppercased()
        } else if let format, !format.isEmpty {
            formatter.positiveFormat = format
        }
        return formatter
    }

    private func isSafeSequenceFormat(_ format: String) -> Bool {
        var conversions = 0
        var index = format.startIndex
        while index < format.endIndex {
            guard format[index] == "%" else {
                index = format.index(after: index)
                continue
            }
            let next = format.index(after: index)
            guard next < format.endIndex else { return false }
            if format[next] == "%" {
                index = format.index(after: next)
                continue
            }
            var cursor = next
            while cursor < format.endIndex, "0123456789-+ .".contains(format[cursor]) {
                cursor = format.index(after: cursor)
            }
            guard cursor < format.endIndex, format[cursor] == "d" else { return false }
            conversions += 1
            index = format.index(after: cursor)
        }
        return conversions == 1
    }
}
