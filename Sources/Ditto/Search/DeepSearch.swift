import Foundation
import CoreML

// MARK: - Levels & modes

/// Embedding model tier (selects which on-device model produces vectors).
/// Until a CoreML model is bundled for a tier, the engine falls back to the
/// dependency-free `HashingEmbedder` so everything still works.
enum DeepSearchLevel: String, CaseIterable, Identifiable {
    case off, low, normal, high
    var id: String { rawValue }

    var title: String {
        switch self {
        case .off:    return "Off"
        case .low:    return "Low (ogma-micro)"
        case .normal: return "Normal (ogma-small)"
        case .high:   return "High (EmbeddingGemma)"
        }
    }

    /// Bundled CoreML model name (`<name>.mlmodelc`) for this tier.
    /// high also drives image search (via OCR text).
    /// - low → axiotic/ogma-micro (2.3M, 128-dim)
    /// - normal → axiotic/ogma-small (8.6M, 256-dim)
    /// - high → google/embeddinggemma-300m (768-dim)
    var modelName: String? {
        switch self {
        case .off:    return nil
        case .low:    return "ogma-micro"
        case .normal: return "ogma-small"
        case .high:   return "embeddinggemma-300m"
        }
    }

    /// Output embedding dimension for each tier's model.
    var dimension: Int {
        switch self {
        case .off:    return 256
        case .low:    return 128
        case .normal: return 256
        case .high:   return 768
        }
    }
}

/// How the bar searches.
/// - `exact`: case-insensitive substring (no vectors).
/// - `tag`: classify the query to its nearest preset tag (100 comparisons),
///   then O(1) lookup of entries pre-tagged at ingest — no per-item dot product.
/// - `essence`: full query·item cosine over every entry's stored vector.
enum SearchMode: String, CaseIterable, Identifiable {
    case exact, tag, essence
    var id: String { rawValue }
    var title: String {
        switch self {
        case .exact:   return "Exact"
        case .tag:     return "Tag"
        case .essence: return "Essence"
        }
    }
}

enum DeepSearch {
    static var level: DeepSearchLevel {
        get { DeepSearchLevel(rawValue: UserDefaults.standard.string(forKey: "deepSearchLevel") ?? "off") ?? .off }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "deepSearchLevel") }
    }
    static var mode: SearchMode {
        get { SearchMode(rawValue: UserDefaults.standard.string(forKey: "searchMode") ?? "exact") ?? .exact }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "searchMode") }
    }
}

// MARK: - Embedding

protocol TextEmbedder {
    var dimension: Int { get }
    func embed(_ text: String) -> [Float]
}

/// Real, dependency-free embedder: hashed character tri-grams + word tokens,
/// L2-normalised. Gives fuzzy/sub-token matching and is the fallback whenever a
/// CoreML model isn't bundled. Deterministic (uses a stable FNV-1a hash, not
/// `Hasher`, so vectors persisted on disk stay valid across launches).
struct HashingEmbedder: TextEmbedder {
    let dimension: Int = 256

    func embed(_ text: String) -> [Float] {
        var vec = [Float](repeating: 0, count: dimension)
        let lower = text.lowercased()
        for token in lower.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            vec[Int(Self.fnv1a(String(token)) % UInt64(dimension))] += 1
        }
        let chars = Array(lower)
        if chars.count >= 3 {
            for i in 0...(chars.count - 3) {
                vec[Int(Self.fnv1a(String(chars[i..<i + 3])) % UInt64(dimension))] += 1
            }
        }
        return Self.normalize(vec)
    }

    /// Stable across processes (unlike Swift's randomized `Hasher`).
    static func fnv1a(_ s: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in s.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    static func normalize(_ v: [Float]) -> [Float] {
        let norm = (v.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return norm > 0 ? v.map { $0 / norm } : v
    }
}

/// Loads a compiled CoreML embedding model bundled in the app; `nil` when the
/// model for a tier isn't bundled yet (callers fall back to `HashingEmbedder`).
/// Real ogma/EmbeddingGemma wiring still needs a `<name>.mlmodelc` in Resources
/// plus a tokenizer + mean-pooling in `embed` (SPEC Tier 7, P-deep-search).
struct CoreMLEmbedder: TextEmbedder {
    let dimension: Int

    init?(modelName: String) {
        // The ogma/EmbeddingGemma CoreML models are converted & bundled (parity
        // 1.0 vs PyTorch), and the model's forward already returns a pooled,
        // L2-normalised vector. What's left is the Swift Unigram tokenizer +
        // `MLModel.prediction`. Until that's wired, stay DISABLED so the engine
        // uses the HashingEmbedder fallback instead of zero vectors.
        return nil
    }

    func embed(_ text: String) -> [Float] { [Float](repeating: 0, count: dimension) }
}

enum EmbedderProvider {
    /// Cached embedder for a level (recomputed only when the level changes).
    private static var cache: (DeepSearchLevel, TextEmbedder)?

    static func embedder(for level: DeepSearchLevel) -> TextEmbedder {
        if let (lvl, emb) = cache, lvl == level { return emb }
        let emb: TextEmbedder = {
            if let name = level.modelName, let core = CoreMLEmbedder(modelName: name) { return core }
            return HashingEmbedder()
        }()
        cache = (level, emb)
        return emb
    }

    static var current: TextEmbedder { embedder(for: DeepSearch.level == .off ? .low : DeepSearch.level) }
}

// MARK: - Preset tag taxonomy (100 tags)

enum TagSpace {
    /// 100 fixed content tags. Index in this array is the stable tag id.
    static let names: [String] = [
        "source code", "error message", "stack trace", "log line", "shell command",
        "terminal output", "git commit", "git diff", "python code", "javascript code",
        "swift code", "html markup", "css style", "sql query", "json data",
        "yaml config", "xml document", "markdown text", "regular expression", "api endpoint",
        "url link", "email address", "phone number", "postal address", "person name",
        "company name", "product name", "date", "time", "number",
        "currency amount", "percentage", "math equation", "uuid", "hash digest",
        "base64 blob", "ip address", "domain name", "file path", "directory path",
        "environment variable", "api key", "access token", "password", "username",
        "configuration", "dependency", "package version", "changelog", "license text",
        "legal clause", "contract term", "invoice", "receipt", "order number",
        "tracking number", "flight booking", "hotel booking", "meeting invite", "calendar event",
        "deadline", "reminder", "task item", "todo note", "project name",
        "ticket id", "issue report", "bug report", "feature request", "design note",
        "color value", "hex color", "font name", "image caption", "alt text",
        "translation", "quotation", "citation", "bibliography reference", "question",
        "answer", "definition", "instruction", "recipe", "ingredient list",
        "measurement", "coordinate", "country", "city", "language",
        "greeting", "signature", "title heading", "bullet list", "table data",
        "csv row", "spreadsheet cell", "math formula", "chemical formula", "miscellaneous text"
    ]

    static var count: Int { names.count }

    /// Tag vectors in the active embedder's space, cached per embedder dimension.
    private static var cache: (Int, [[Float]])?

    static func vectors(using embedder: TextEmbedder) -> [[Float]] {
        if let (dim, v) = cache, dim == embedder.dimension { return v }
        let v = names.map { embedder.embed($0) }
        cache = (embedder.dimension, v)
        return v
    }

    /// Top-K nearest tag ids for an entry vector.
    static func classify(_ vector: [Float], embedder: TextEmbedder, topK: Int = 5) -> [Int] {
        guard !vector.isEmpty else { return [] }
        let tagVecs = vectors(using: embedder)
        let scored = tagVecs.enumerated().map { ($0.offset, SemanticRanker.cosine(vector, $0.element)) }
        return scored.sorted { $0.1 > $1.1 }.prefix(topK).map { $0.0 }
    }

    /// Nearest single tag id for a query (used by tag search).
    static func nearestTag(toQuery query: String, embedder: TextEmbedder) -> Int? {
        classify(embedder.embed(query), embedder: embedder, topK: 1).first
    }
}

// MARK: - Ingest indexing

enum ClipIndexer {
    /// Compute and attach the entry's vector + top-5 tag ids using the active
    /// model tier. Idempotent-ish: always recomputes from the current embedder.
    static func index(_ item: ClipItem) {
        let embedder = EmbedderProvider.current
        let vec = embedder.embed(SemanticRanker.searchText(item))
        item.vector = vec
        item.tagIDs = TagSpace.classify(vec, embedder: embedder, topK: 5)
    }
}

// MARK: - Ranking

enum SemanticRanker {
    static func searchText(_ item: ClipItem) -> String {
        switch item.kind {
        case .file:  return (item.filePath as NSString?)?.lastPathComponent ?? item.text
        case .color: return item.colorHex ?? item.text
        default:     return item.text
        }
    }

    static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        var dot: Float = 0
        for i in a.indices { dot += a[i] * b[i] }
        return dot // inputs L2-normalised
    }

    /// Essence search: full query·item cosine, best-first, thresholded.
    static func essence(query: String, items: [ClipItem], embedder: TextEmbedder) -> [ClipItem] {
        let qv = embedder.embed(query)
        let q = query.lowercased()
        let scored = items.map { item -> (ClipItem, Float) in
            let vec = item.vector ?? embedder.embed(searchText(item))
            let substring = searchText(item).lowercased().contains(q)
            return (item, (substring ? 1 : 0) + cosine(qv, vec))
        }
        let kept = scored.filter { $0.1 >= 0.12 }.sorted { $0.1 > $1.1 }
        return (kept.isEmpty ? scored.sorted { $0.1 > $1.1 }.prefix(min(items.count, 12)).map { ($0.0, $0.1) }
                             : kept).map { $0.0 }
    }
}
