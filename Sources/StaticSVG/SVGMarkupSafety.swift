import Foundation

/// Refuses entity declarations and internal DTD subsets before the XML parser runs, and caps the
/// attributes in one tag, which also caps the parser's quadratic attribute uniqueness check.
/// Comments, CDATA, processing instructions and quoted identifiers are not declarations. The
/// bytes are UTF-8, the encoding the parser is told to read whatever the document declares.
enum SVGMarkupSafety {
    static let attributesPerElement = 1024
    enum Assessment: Equatable { case safe, unsafe, attributeLimitExceeded }

    static func assess(_ data: Data) -> Assessment {
        let bytes = Array(data)
        var attributes = AttributeScanner(bytes: bytes, limit: attributesPerElement)
        guard attributes.scan() else { return .attributeLimitExceeded }
        var declarations = DeclarationScanner(bytes: bytes)
        return declarations.scan() ? .safe : .unsafe
    }
}

/// Follows XML's lexical rules, which every well-formed document obeys. Where a document breaks
/// them, a `<` no markup can follow and, in an element's tag, a quote no attribute value can open
/// are characters: the XML parser stops at either one whatever this scan says, and taking it for
/// markup would only hide what follows from the scan.
private struct DeclarationScanner {
    let bytes: [UInt8]
    var index = 0

    mutating func scan() -> Bool {
        while index < bytes.count {
            guard bytes[index] == 0x3C else { index += 1; continue } // <
            // A stray sign in prose (`x < y`) or a style sheet (`content: "<"`) is a character,
            // not a tag whose quotes and `>` would be sought through the text after it.
            guard opensMarkup else { index += 1; continue }
            if consume("<!--") {
                guard skip(until: "-->") else { return false }
            } else if consume("<![CDATA[") {
                guard skip(until: "]]>") else { return false }
            } else if consume("<?") {
                guard skip(until: "?>") else { return false }
            } else if consume("<!ENTITY") {
                return false
            } else if consume("<!DOCTYPE") {
                guard endTag(rejectSubset: true) else { return false }
                // libxml2 reads a `[` directly after the closing `>` as the internal subset too.
                if index < bytes.count, bytes[index] == 0x5B { return false }
            } else if consume("<!") {
                guard endTag(rejectSubset: false) else { return false }
            } else {
                index += 1
                guard endElementTag() else { return false }
            }
        }
        return true
    }

    /// Whether the `<` at `index` can open markup: a name start (any non-ASCII byte may be one),
    /// `/`, `!` or `?` follows. At the end of input it is markup left open.
    private var opensMarkup: Bool {
        guard index + 1 < bytes.count else { return true }
        let next = bytes[index + 1]
        let letter = next | 0x20
        return (letter >= 0x61 && letter <= 0x7A) || next >= 0x80
            || next == 0x2F || next == 0x21 || next == 0x3F || next == 0x3A || next == 0x5F // / ! ? : _
    }

    private mutating func consume(_ token: StaticString) -> Bool {
        token.withUTF8Buffer { buffer in
            guard bytes[index...].starts(with: buffer) else { return false }
            index += buffer.count
            return true
        }
    }

    private mutating func skip(until token: StaticString) -> Bool {
        while index < bytes.count {
            if consume(token) { return true }
            index += 1
        }
        return false
    }

    /// Scans through the `>` that ends a declaration, whose literals are quoted wherever they
    /// stand (`<!ATTLIST x a CDATA "=">`).
    private mutating func endTag(rejectSubset: Bool) -> Bool {
        var quote: UInt8?
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if let delimiter = quote {
                if byte == delimiter { quote = nil }
            } else if byte == 0x22 || byte == 0x27 { // double or single quote
                quote = byte
            } else if byte == 0x3E { // >
                return true
            } else if rejectSubset && byte == 0x5B { // [
                return false
            }
        }
        return false
    }

    /// Scans through the `>` that ends an element's tag. A quote there delimits only an attribute
    /// value, after `=`: anywhere else (`<y then it's`) it is a character and hides nothing.
    private mutating func endElementTag() -> Bool {
        var quote: UInt8?
        var valueFollows = false
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if let delimiter = quote {
                if byte == delimiter { quote = nil }
            } else if valueFollows && (byte == 0x22 || byte == 0x27) { // double or single quote
                quote = byte
                valueFollows = false
            } else if byte == 0x3E { // >
                return true
            } else if byte == 0x3D { // =
                valueFollows = true
            } else if byte != 0x20 && byte != 0x09 && byte != 0x0A && byte != 0x0D { // not XML white space
                valueFollows = false
            }
        }
        return false
    }
}

/// Counts the attributes in each tag, duplicates included, as the XML parser would read them.
private struct AttributeScanner {
    let bytes: [UInt8]
    let limit: Int
    var index = 0

    mutating func scan() -> Bool {
        while index < bytes.count {
            guard bytes[index] == 0x3C else { index += 1; continue }
            if consume("<!--") { skip("-->"); continue }
            if consume("<![CDATA[") { skip("]]>"); continue }
            if consume("<?") { skip("?>"); continue }
            index += 1
            guard index < bytes.count else { break }
            let byte = bytes[index] | 0x20
            guard (byte >= 0x61 && byte <= 0x7A) || bytes[index] >= 0x80 || [0x3A, 0x5F].contains(bytes[index]) else { continue }
            while index < bytes.count, !space(bytes[index]), ![0x2F, 0x3E].contains(bytes[index]) { index += 1 }
            var attributes = 0
            while index < bytes.count {
                while index < bytes.count, space(bytes[index]) || bytes[index] == 0x2F { index += 1 }
                guard index < bytes.count else { break }
                if bytes[index] == 0x3E { index += 1; break }
                attributes += 1
                guard attributes <= limit else { return false }
                // At least one byte, even for an invalid name, ensures forward progress.
                index += 1
                while index < bytes.count, !space(bytes[index]), ![0x2F, 0x3D, 0x3E].contains(bytes[index]) { index += 1 }
                while index < bytes.count, space(bytes[index]) { index += 1 }
                guard index < bytes.count, bytes[index] == 0x3D else { continue }
                index += 1
                while index < bytes.count, space(bytes[index]) { index += 1 }
                if index < bytes.count, bytes[index] == 0x22 || bytes[index] == 0x27 {
                    let quote = bytes[index]; index += 1
                    while index < bytes.count, bytes[index] != quote { index += 1 }
                    if index < bytes.count { index += 1 }
                } else {
                    while index < bytes.count, !space(bytes[index]), bytes[index] != 0x3E { index += 1 }
                }
            }
        }
        return true
    }

    private func space(_ byte: UInt8) -> Bool { [0x20, 0x09, 0x0A, 0x0C, 0x0D].contains(byte) }
    private mutating func consume(_ token: StaticString) -> Bool {
        token.withUTF8Buffer {
            guard bytes[index...].starts(with: $0) else { return false }
            index += $0.count; return true
        }
    }
    private mutating func skip(_ token: StaticString) {
        while index < bytes.count {
            if consume(token) { return }
            index += 1
        }
    }
}
