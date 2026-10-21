import Foundation
import libxml2

/// One node of an SVG document: an element or its character data.
///
/// Only element and character-data nodes exist. Comments and processing instructions are
/// dropped and adjacent text and CDATA are merged into one text node. A node is immutable once
/// its document is built, and the whole tree may be read from any thread.
public final class SVGNode: @unchecked Sendable {
    public enum Kind: Sendable { case element, text }

    public let kind: Kind
    /// Local name. Empty for text.
    public let name: String
    /// Namespace URI, or "" when none.
    public let namespace: String
    public let attributes: [SVGAttribute]
    /// Character data, entities decoded. Empty for elements.
    public let text: String
    public fileprivate(set) var children: [SVGNode] = []
    public fileprivate(set) weak var parent: SVGNode?
    /// Preorder index in its document. `document.nodes[order] === self`.
    fileprivate(set) var order = 0
    /// Order of the last node in this node's subtree (itself when it has no children).
    fileprivate(set) var subtreeEnd = 0

    fileprivate init(element name: String, namespace: String, attributes: [SVGAttribute]) {
        kind = .element; self.name = name; self.namespace = namespace
        self.attributes = attributes; text = ""
    }
    fileprivate init(text: String) {
        kind = .text; name = ""; namespace = ""; attributes = []; self.text = text
    }

    public var isElement: Bool { kind == .element }
    public var isText: Bool { kind == .text }

    /// The value of an attribute by local name; `namespace` nil matches an attribute in no namespace.
    public func attribute(_ local: String, namespace: String? = nil) -> String? {
        attributes.first { $0.name == local && $0.namespace == (namespace ?? "") }?.value
    }
    public var elementChildren: [SVGNode] { children.filter(\.isElement) }
    /// Concatenated descendant text, in document order.
    public var textContent: String {
        isText ? text : children.map(\.textContent).joined()
    }
}

public struct SVGAttribute: Equatable, Sendable {
    /// Local name.
    public let name: String
    /// Namespace URI, or "" when none.
    public let namespace: String
    public let value: String

    public init(name: String, namespace: String = "", value: String) {
        self.name = name; self.namespace = namespace; self.value = value
    }
}

public enum SVGNamespace {
    public static let svg = "http://www.w3.org/2000/svg"
    public static let xlink = "http://www.w3.org/1999/xlink"
    public static let xml = "http://www.w3.org/XML/1998/namespace"
    public static let xhtml = "http://www.w3.org/1999/xhtml"
}

/// Structural bounds on a document, checked while it is parsed or built.
public struct SVGLimits: Equatable, Sendable {
    /// Bytes of markup `SVGDocument.parse` reads at most. A built document has no markup.
    public var bytes: Int
    /// Element nesting: the root is at depth 0, and an element at `depth` or deeper is refused.
    public var depth: Int
    /// Element and text nodes together.
    public var nodes: Int

    public init(bytes: Int, depth: Int, nodes: Int) {
        self.bytes = bytes; self.depth = depth; self.nodes = nodes
    }

    /// What `SVGRenderer` parses the exact bytes it is given with: the bounds a drawing must
    /// keep to before anything else is screened.
    public static let renderer = SVGLimits(bytes: SVGContent.maximumBytes, depth: SVGContent.maximumDepth,
                                           nodes: SVGContent.maximumNodes)
    /// A document a host parses or builds before serializing it. The drawing limits are applied
    /// by the screens, which name what they refuse, so a document can be larger than a drawing.
    public static let document = SVGLimits(bytes: 8 * 1024 * 1024, depth: 200, nodes: 250_000)
}

public enum SVGDocumentError: Error, Equatable, Sendable {
    /// Entity declarations, an internal DTD subset or too many attributes in one tag: refused
    /// before parsing.
    case unsafeMarkup
    /// The bytes are not UTF-8, the only encoding the renderer reads, or they declare an encoding
    /// that would read them otherwise.
    case notUTF8
    /// Not well-formed, namespace-well-formed XML, or an entity reference nothing declares.
    case malformed
    /// The named bound of `SVGLimits` was exceeded.
    case limitExceeded(String)
}

/// A parsed or host-built SVG document: its root element and every node in preorder.
public final class SVGDocument: @unchecked Sendable {
    public let root: SVGNode
    /// Every node in preorder; `nodes[n.order] === n`.
    public let nodes: [SVGNode]

    fileprivate init(root: SVGNode, nodes: [SVGNode]) {
        self.root = root; self.nodes = nodes
    }

    /// Parses UTF-8 XML. Entity declarations and internal DTD subsets are refused before the
    /// parser runs, and no external DTD or entity is loaded. The bytes are read as UTF-8, as the
    /// renderer reads them; a declaration of another encoding is accepted only where that encoding
    /// reads the bytes as the same text (`readsAsDeclared`).
    public static func parse(_ data: Data, limits: SVGLimits = .document) throws -> SVGDocument {
        guard data.count <= limits.bytes, data.count <= Int(Int32.max) else { throw SVGDocumentError.limitExceeded("bytes") }
        guard let text = String(validating: data, as: UTF8.self), readsAsDeclared(data, text: text) else {
            throw SVGDocumentError.notUTF8
        }
        switch SVGMarkupSafety.assess(data) {
        case .safe: break
        case .attributeLimitExceeded: throw SVGDocumentError.limitExceeded("attributesPerElement")
        case .unsafe: throw SVGDocumentError.unsafeMarkup
        }
        guard let document = try parseXML(data, limits: limits) else { throw SVGDocumentError.malformed }
        return document
    }

    /// Whether the encoding an XML declaration names reads `data` as the text UTF-8 gives. The
    /// renderer reads every drawing as UTF-8 whatever it declares, and so does this parser, so a
    /// declaration of another encoding that would read the bytes otherwise (UTF-16 over UTF-8
    /// bytes, or Latin-1 over non-ASCII ones) is a drawing a reader that honors it would draw
    /// differently: it is refused, as it was when such a drawing was parsed by its declaration
    /// and screened as what that gave. An encoding name nothing here knows is refused too.
    private static func readsAsDeclared(_ data: Data, text: String) -> Bool {
        let head = String(text.prefix(256))
        guard let match = head.firstMatch(of: /^\u{FEFF}?<\?xml\s[^>]*?encoding\s*=\s*["']([A-Za-z0-9._:-]+)["']/) else { return true }
        let name = String(match.1).lowercased()
        if name == "utf-8" || name == "utf8" { return true }
        let encoding = CFStringConvertIANACharSetNameToEncoding(name as CFString)
        guard encoding != kCFStringEncodingInvalidId,
              let declared = String(data: data, encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding))) else {
            return false
        }
        return declared == text
    }

    private static let xmlOptions = Int32(XML_PARSE_NONET.rawValue | XML_PARSE_NOERROR.rawValue
        | XML_PARSE_NOWARNING.rawValue | XML_PARSE_NOCDATA.rawValue)

    private static func parseXML(_ data: Data, limits: SVGLimits) throws -> SVGDocument? {
        // libxml2 may return a tree for namespace errors and undeclared entities under
        // an external DOCTYPE. Inspect this parse's own diagnostics, never a global
        // error or only lastError: a later URI warning can hide an earlier QName error.
        let namespaceError = UnsafeMutablePointer<Bool>.allocate(capacity: 1)
        namespaceError.initialize(to: false)
        defer { namespaceError.deinitialize(count: 1); namespaceError.deallocate() }
        guard let context = xmlNewParserCtxt() else { return nil }
        defer { xmlFreeParserCtxt(context) }
        context.pointee._private = UnsafeMutableRawPointer(namespaceError)
        context.pointee.sax?.pointee.serror = { raw, error in
            guard let raw, let error, error.pointee.domain == Int32(XML_FROM_NAMESPACE.rawValue) else { return }
            switch error.pointee.code {
            // libxml2 marks an unusual namespace URI as an error and clears
            // nsWellFormed, although an unknown URI does not invalidate a QName.
            case Int32(XML_WAR_NS_URI.rawValue), Int32(XML_WAR_NS_URI_RELATIVE.rawValue): return
            default: break
            }
            guard error.pointee.level.rawValue >= XML_ERR_ERROR.rawValue else { return }
            let parser = raw.assumingMemoryBound(to: xmlParserCtxt.self)
            parser.pointee._private?.assumingMemoryBound(to: Bool.self).pointee = true
        }
        let doc = SVGLibXML2Messages.silenced {
            data.withUnsafeBytes { buffer in
                xmlCtxtReadMemory(context, buffer.baseAddress?.assumingMemoryBound(to: CChar.self), Int32(buffer.count),
                                  nil, "UTF-8", xmlOptions)
            }
        }
        guard let doc else { return nil }
        defer { xmlFreeDoc(doc) }
        guard context.pointee.wellFormed != 0, !namespaceError.pointee else { return nil }
        do {
            return try convert(doc, limits: limits)
        } catch TreeError.unresolvedEntity {
            return nil
        }
    }

    private enum TreeError: Error { case unresolvedEntity }

    private static func convert(_ doc: xmlDocPtr, limits: SVGLimits) throws -> SVGDocument? {
        guard let rootElement = xmlDocGetRootElement(doc) else { return nil }
        var builder = Builder(limits: limits)
        func string(_ value: UnsafePointer<xmlChar>?) -> String { value.map { String(cString: $0) } ?? "" }
        func build(_ xml: xmlNodePtr) throws {
            let namespace = string(xml.pointee.ns?.pointee.href)
            let rawName = string(xml.pointee.name)
            var attributes: [SVGAttribute] = []
            var attribute = xml.pointee.properties
            while let current = attribute {
                var value = ""
                var part = current.pointee.children
                while let text = part {
                    if text.pointee.type == XML_ENTITY_REF_NODE, text.pointee.children == nil { throw TreeError.unresolvedEntity }
                    if let content = text.pointee.content { value += String(cString: content) }
                    part = text.pointee.next
                }
                attributes.append(SVGAttribute(name: string(current.pointee.name),
                                               namespace: string(current.pointee.ns?.pointee.href), value: value))
                attribute = current.pointee.next
            }
            try builder.startElement(namespace == SVGNamespace.xhtml ? rawName.lowercased() : rawName,
                                     namespace: namespace, attributes: attributes)
            var child = xml.pointee.children
            while let current = child {
                switch current.pointee.type {
                case XML_ELEMENT_NODE:
                    try build(current)
                case XML_TEXT_NODE, XML_CDATA_SECTION_NODE:
                    try builder.appendText(current.pointee.content.map { String(cString: $0) } ?? "")
                case XML_ENTITY_REF_NODE:
                    // An external DTD makes an undeclared entity only a warning in libxml2.
                    // Refuse that tree instead of dropping its empty node.
                    guard let entity = current.pointee.children else { throw TreeError.unresolvedEntity }
                    if let content = entity.pointee.content { try builder.appendText(String(cString: content)) }
                default: break // Comments, processing instructions, DTD nodes.
                }
                child = current.pointee.next
            }
            try builder.endElement()
        }
        try build(rootElement)
        return try builder.finish()
    }

    /// Builds a document from a host's own tree, such as an `<svg>` element inside an XHTML
    /// page, one start, text and end at a time. Adjacent text is merged. The limits are checked
    /// as nodes arrive, so a host never builds more than they allow.
    public struct Builder {
        private let limits: SVGLimits
        private var nodes: [SVGNode] = []
        private var open: [SVGNode] = []
        private var pendingText = ""
        private var hasPendingText = false
        private var root: SVGNode?

        public init(limits: SVGLimits = .document) { self.limits = limits }

        /// Opens an element as the next child of the element open, or as the root.
        public mutating func startElement(_ name: String, namespace: String = "", attributes: [SVGAttribute] = []) throws {
            guard root == nil || !open.isEmpty else { throw SVGDocumentError.malformed }
            guard open.count < limits.depth else { throw SVGDocumentError.limitExceeded("depth") }
            try flushText()
            let node = SVGNode(element: name, namespace: namespace, attributes: attributes)
            try append(node)
            if root == nil { root = node }
            open.append(node)
        }

        /// Adds character data to the element open.
        public mutating func appendText(_ text: String) throws {
            guard !open.isEmpty else { throw SVGDocumentError.malformed }
            pendingText += text
            hasPendingText = true
        }

        /// Closes the element open.
        public mutating func endElement() throws {
            guard let node = open.last else { throw SVGDocumentError.malformed }
            try flushText()
            node.subtreeEnd = nodes.count - 1
            open.removeLast()
        }

        /// The document, once every element opened has been closed.
        public func finish() throws -> SVGDocument {
            guard let root, open.isEmpty else { throw SVGDocumentError.malformed }
            return SVGDocument(root: root, nodes: nodes)
        }

        private mutating func append(_ node: SVGNode) throws {
            node.order = nodes.count
            node.subtreeEnd = node.order
            if let parent = open.last {
                node.parent = parent
                parent.children.append(node)
            }
            nodes.append(node)
            guard nodes.count <= limits.nodes else { throw SVGDocumentError.limitExceeded("nodes") }
        }

        private mutating func flushText() throws {
            guard hasPendingText else { return }
            let text = SVGNode(text: pendingText)
            pendingText = ""; hasPendingText = false
            try append(text)
        }
    }
}

/// Keeps libxml2's messages about a document off the host's standard error.
///
/// `XML_PARSE_NOERROR` does not reach every message: an error in decoding the bytes is raised
/// with no parser at all and goes to this thread's handlers, which libxml2 keeps per thread. For
/// the call they take everything and write nowhere; then the thread's own come back, so a host's
/// handlers, and the messages of its own libxml2 calls, are as they were.
enum SVGLibXML2Messages {
    static func silenced<T>(_ body: () throws -> T) rethrows -> T {
        let structured = (__xmlStructuredError()?.pointee, __xmlStructuredErrorContext()?.pointee)
        let generic = (__xmlGenericError()?.pointee, __xmlGenericErrorContext()?.pointee)
        xmlSetStructuredErrorFunc(nil) { _, _ in }
        // Named no handler, libxml2's default generic one writes to the context as a FILE.
        xmlSetGenericErrorFunc(sink, nil)
        defer {
            xmlSetStructuredErrorFunc(structured.1, structured.0)
            xmlSetGenericErrorFunc(generic.1, generic.0)
        }
        return try body()
    }

    /// A FILE whose writes go nowhere.
    private nonisolated(unsafe) static let sink = UnsafeMutableRawPointer(funopen(nil, nil, { _, _, count in count }, nil, nil))
}

/// An element ID, or a name a reference can point to, compared and hashed code unit for code
/// unit, as the renderer compares it. `String` compares by canonical equivalence, under which
/// `caf\u{E9}` and `cafe\u{301}` are equal, so a table keyed by `String` would hold one of two
/// elements the renderer tells apart.
struct SVGElementID: Hashable, Sendable, ExpressibleByStringLiteral, CustomStringConvertible {
    let string: String
    init(_ string: String) { self.string = string }
    init(stringLiteral string: String) { self.string = string }
    var description: String { string }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.string.utf8.elementsEqual(rhs.string.utf8) }

    func hash(into hasher: inout Hasher) {
        var string = string
        string.withUTF8 { hasher.combine(bytes: UnsafeRawBufferPointer($0)) }
    }
}

extension Dictionary where Key == SVGElementID {
    /// The value under the ID with these code units.
    subscript(_ id: String) -> Value? {
        get { self[SVGElementID(id)] }
        set { self[SVGElementID(id)] = newValue }
    }
}
