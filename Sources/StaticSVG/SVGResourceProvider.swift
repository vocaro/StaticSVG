import Foundation

/// Supplies the images a drawing's `<image>` elements name. StaticSVG opens no file and fetches
/// no URL: apart from a `data:` URL in the drawing itself, every byte it reads comes through
/// this, and only during `SVGDocument.serialized`. The calls are made on the serializing thread,
/// one at a time.
public protocol SVGResourceProvider {
    /// The resources to try, in order, for the one at `path`: itself, then any fallbacks a host
    /// keeps for it. The first that prepares as a bounded image is used. A host leaves out
    /// whatever it will not read, such as a remote resource.
    func imageCandidates(for path: String) -> [String]

    /// The bytes of the resource at `path`, or nil when there are none to read. Asked once for a
    /// path in one serialization at most; a result is memoized with the image it prepares.
    func data(at path: String) -> Data?

    /// The media type a host records for the resource at `path`, if any. An SVG is recognized
    /// by it, by a `.svg` or `.svgz` name, or by its first bytes.
    func mediaType(at path: String) -> String?

    /// The path a reference inside the SVG image at `path` names, for that drawing's own
    /// images; nil when it names nothing the host supplies.
    func resolve(_ reference: String, relativeTo path: String) -> String?

    /// Parses an SVG image found at `path`, which is empty for one in a `data:` URL. By default
    /// `SVGDocument.parse`; a host that reads its SVG files differently, such as with named
    /// character references a publication format allows, parses them its own way here.
    func document(from data: Data, path: String) -> SVGDocument?
}

extension SVGResourceProvider {
    public func imageCandidates(for path: String) -> [String] { [path] }
    public func mediaType(at path: String) -> String? { nil }
    public func resolve(_ reference: String, relativeTo path: String) -> String? { nil }
    public func document(from data: Data, path: String) -> SVGDocument? { try? SVGDocument.parse(data) }
}
