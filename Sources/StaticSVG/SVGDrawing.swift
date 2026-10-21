import CoreGraphics
import Foundation

/// A drawing serialized for the renderer, and what was left out or refused on the way.
public struct SVGSerialization: Sendable {
    /// The sanitized, standalone drawing, or nil when it is refused. Hand it to `SVGRenderer`,
    /// which screens it again.
    public let data: Data?
    /// What was removed or could not be inlined. Present whether or not there is a drawing.
    public let diagnostics: SVGDiagnostics
}

extension SVGDocument {
    /// Whether the root is an `<svg>` element in the SVG namespace, or in none.
    public var isSVG: Bool { root.name == "svg" && SVGContent.isSVG(root, root: root) }

    /// The drawing's own `<title>`, white space collapsed.
    public var title: String? { SVGContent.title(root) }

    /// Its own `<title>` and `<desc>`, white space collapsed and joined by ". ".
    public var accessibleLabel: String? { SVGContent.accessibleLabel(root) }

    /// What to show where the drawing cannot be drawn: `accessibleLabel`, or else the words of
    /// its `<text>`, or else "Illustration unavailable".
    public var fallbackText: String { SVGContent.fallbackText(root) }

    /// The constructs the drawing holds that are never drawn (`script` and the other content
    /// of `SVGDiagnostics.Kind`), filter effects, which are omitted, and pattern fills, which
    /// refuse it. Empty when a nested `<style>` refuses the drawing before it is read.
    public var constructs: Set<SVGDiagnostics.Kind> {
        Set(SVGContent.unsupportedConstructs(root).compactMap(SVGDiagnostics.Kind.init(rawValue:)))
    }

    /// The font families it names, in `font-family` attributes and declarations, lowercased.
    /// A host supplies faces for them to `SVGRenderer`, and may alias them for serialization.
    public var fontFamilies: Set<String> { SVGContent.fontFamilies(root) }

    /// The viewBox, when it has four finite numbers and a positive size.
    public var viewBox: CGRect? { SVGContent.viewBox(root) }

    /// The size of the drawing's box in points: absolute `width` and `height`, with the authored
    /// viewport kept; else the viewBox's; else `fallback`. Lengths in `em` and `ex` use
    /// `fontSize`.
    public func intrinsicSize(fontSize: CGFloat, fallback: CGSize) -> CGSize {
        SVGContent.intrinsicSize(root, fontSize: fontSize, fallback: fallback)
    }

    /// Whether every bound the renderer is screened against holds for this tree: its size and
    /// depth, `<use>` expansion, text runs, stylesheet work, references, geometry, raster
    /// memory, markers and per-shape copies. With `omittingFilters`, filter effects do not
    /// refuse it, as `serialized` omits them.
    public func isWithinRenderingLimits(omittingFilters: Bool = false) -> Bool {
        SVGContent.isWithinRenderingLimits(root, omittingFilters: omittingFilters)
    }

    /// The drawing as a standalone document the renderer can be given. Scripts, foreign
    /// content, animation, filter effects, event attributes and every reference outside the
    /// drawing are removed. Each `<image>` is decoded within the bounds and inlined as PNG:
    /// one in a `data:` URL from its own bytes, any other through `resources`, at the path
    /// `resolve` gives for its reference. Without `resources` only `data:` images are inlined.
    ///
    /// - Parameters:
    ///   - resolve: The path of the resource a reference names, or nil when it names none.
    ///   - fontAliases: Lowercased family names the drawing uses, mapped to the family names of
    ///     the faces that stand for them; a family is written as the face's own name.
    ///   - preparation: The image work budget, which nested drawings share. A fresh one is
    ///     used when nil.
    public func serialized(resolve: (String) -> String? = { _ in nil }, resources: (any SVGResourceProvider)? = nil,
                           fontAliases: [String: String] = [:],
                           preparation: SVGImagePreparation? = nil) -> SVGSerialization {
        let box = SVGDiagnosticsBox()
        let data = SVGContent.serialize(root, resolve: resolve, resources: resources, fontAliases: fontAliases,
                                        report: box, imagePreparation: preparation)
        return SVGSerialization(data: data, diagnostics: box.diagnostics)
    }
}
