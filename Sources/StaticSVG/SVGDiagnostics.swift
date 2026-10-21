import Foundation

/// What StaticSVG left out of a drawing, refused or changed, by kind and number. A host maps it
/// to what it tells its reader; the raw values are stable identifiers a host may show or store.
public struct SVGDiagnostics: Equatable, Sendable {
    public enum Kind: String, CaseIterable, Sendable {
        // Content a static drawing never runs or shows. The drawing is kept without it.
        case script = "svg:script"
        case foreignObject = "svg:foreignObject"
        case iframe = "svg:iframe"
        case video = "svg:video"
        case audio = "svg:audio"
        case handler = "svg:handler"
        case listener = "svg:listener"
        case animate = "svg:animate"
        case animateMotion = "svg:animateMotion"
        case animateTransform = "svg:animateTransform"
        case set = "svg:set"
        /// Filter effects, omitted with the rest of the drawing kept.
        case filter = "svg:filter"
        /// A pattern fill. A drawing that holds one is refused and its fallback text stands in.
        case pattern = "svg:pattern"
        /// A stylesheet removed whole: it imports another or reaches outside the drawing.
        case stylesheet = "svg:style"
        /// An `<image>` that could not be inlined: unresolved, unreadable, undecodable or over
        /// a bound.
        case image = "svg:image"
        /// An attribute whose CSS could reach outside the drawing, removed.
        case attribute = "svg:attribute"
        /// A font whose color glyph tables were removed so that only its outlines draw
        /// (`SVGFontData.strippedColorGlyphs`).
        case colorGlyphs = "svg:font-color"
    }

    /// Counts by kind; a kind not present counts zero.
    public private(set) var counts: [Kind: Int] = [:]

    public init() {}

    public subscript(kind: Kind) -> Int { counts[kind] ?? 0 }
    public var isEmpty: Bool { counts.isEmpty }

    /// Counts can grow much faster than prepared bytes where one image is drawn through a
    /// repeated DAG of nested drawings. Merged counts keep to this, which leaves headroom for a
    /// host's own increments and aggregation.
    public static let maximumMergedCount = Int.max / (1024 * 1024)

    /// Adds `count` of `kind`.
    public mutating func record(_ kind: Kind, count: Int = 1) {
        counts[kind, default: 0] += count
    }

    /// Adds another's counts, each capped so that a merge never takes a count past
    /// `maximumMergedCount`. A count already past it is left as it is.
    public mutating func formCappedUnion(_ other: SVGDiagnostics) {
        for (kind, count) in other.counts {
            let current = counts[kind] ?? 0
            let added = min(count, max(0, Self.maximumMergedCount - current))
            if added > 0 { counts[kind] = current + added }
        }
    }
}

/// The diagnostics of one serialization in progress, shared by the drawings nested in it.
final class SVGDiagnosticsBox {
    var diagnostics = SVGDiagnostics()
}
