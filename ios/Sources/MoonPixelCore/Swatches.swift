import Foundation

// Figures share their shapes: a person's colours are kept apart from the person's model.
//
// A figure mesh normally carries its colours in its texture coordinates (each face points at its colour in the
// one palette texture, `Palette3D`), so two people who differ only in the colour of a shirt need two meshes, and
// a crowd of a hundred people walking in three steps needs three hundred. With a `SwatchBook` the faces point
// instead into a small strip of swatches: one column per base colour the model was built with, one row per tone
// (as painted, lit, shadow, deep shadow). The model is built once, from a stand-in look, for everyone of the
// same shape (the same figure, hair style, sex, age, step and tool: `AnimeRigs`); each person brings only a strip
// of their own colours (a few hundred bytes) that the model is drawn with.
//
// A person's strip is found by building the person's own figure once with a recording book and pairing its
// faces, in order, with the stand-in's: whatever colour the stand-in has at a face, the person has theirs. When
// two of the stand-in's colours would have to be one (it never happens with the stand-in's colours, but it is
// checked), the person is drawn the old way, with a model of their own.

/// Swatches of a family of figures: the base colours their faces were built with, by column.
public final class SwatchBook {
    public static let width = 128, tones = 4
    /// The base colour of each column (as the stand-in look made them).
    public private(set) var bases: [RGBA] = []
    private var index: [UInt32: Int] = [:]
    /// Every face's base colour in the order they were made (a recording book only).
    public var calls: [RGBA]?
    /// More colours than columns were asked for: the models made with this book are wrong.
    public private(set) var overflow = false

    public init(recording: Bool = false) { calls = recording ? [] : nil }

    static func key(_ c: RGBA) -> UInt32 { UInt32(c.r) << 24 | UInt32(c.g) << 16 | UInt32(c.b) << 8 | UInt32(c.a) }

    /// The column of a base colour (nil when the book has none).
    public func column(of c: RGBA) -> Int? { index[SwatchBook.key(c)] }

    /// The texture coordinate of a base colour in a tone (a new column when the colour is new).
    public func uv(_ base: RGBA, tone: Int) -> SIMD2<Float> {
        calls?.append(base)
        let k = SwatchBook.key(base)
        let i: Int
        if let j = index[k] { i = j }
        else if bases.count < SwatchBook.width { i = bases.count; bases.append(base); index[k] = i }
        else { overflow = true; i = 0 }
        // the strip is mirrored top to bottom (tone t in row t and in the row as far from the bottom), so it
        // reads the same whichever way a renderer turns its pictures' v
        return SIMD2((Float(i) + 0.5) / Float(SwatchBook.width), (Float(Swift.max(0, Swift.min(SwatchBook.tones - 1, tone))) + 0.5) / Float(2 * SwatchBook.tones))
    }

    /// The tone row of a cel-shaded face with this shade (0 is "as painted", for unshaded faces).
    public static func tone(shade: Double) -> Int { shade <= 0.001 ? 1 : (shade < 0.3 ? 2 : 3) }

    /// A base colour in a tone: what `Mesh3D.celColor` makes of it.
    public static func toned(_ c: RGBA, _ tone: Int) -> RGBA {
        switch tone {
        case 0: return c
        case 1: return Mesh3D.celColor(c, shade: 0)
        case 2: return Mesh3D.celColor(c, shade: 0.2)
        default: return Mesh3D.celColor(c, shade: 0.4)
        }
    }

    /// The strip of swatches for base colours by column (columns past them in `fill`).
    public static func strip(_ colors: [RGBA], fill: RGBA = Mesh3D.ink) -> Bitmap {
        var b = Bitmap(width, 2 * tones)
        for x in 0..<width { for t in 0..<tones {
            let c = toned(x < colors.count ? colors[x] : fill, t)
            b.set(x, t, c); b.set(x, 2 * tones - 1 - t, c)
        } }
        return b
    }
}

/// The shared anime figures: one model per shape for everyone, one strip of colours per person.
public final class AnimeRigs {
    /// The look the shared models are built in (its colours are never seen: each person brings their own).
    public static let standIn: Look = {
        var l = Look()
        l.skin = "#f0c4a8"; l.hair = "#3a5ab0"; l.shirt = "#b03848"; l.pants = "#3c9a64"; l.shoes = "#7a5a1c"
        return l
    }()

    final class Family {
        let book = SwatchBook()
        var standInCalls: [RGBA] = []
    }
    private var families: [String: Family] = [:]

    public init() {}

    /// The family of a person's figure (what decides the shape besides the step and the tool); nil for a
    /// character model (a knight, a merfolk...), which is drawn with a model of its own.
    public static func family(_ look: Look, child: Bool, female: Bool, kind: AnimeArt.Figure, lite: Bool) -> String? {
        guard CharacterModels.of(look.model) == nil else { return nil }
        // the hair is the only part the style shapes (Figure3D.anime): long, twin tails, a bun
        let st = look.style
        let hair = (female || st % 3 == 1 ? 1 : 0) + (female && st % 4 == 3 ? 2 : (st % 3 == 2 ? 4 : 0))
        return "\(kind.rawValue)\(lite ? "l" : "f")\(child ? "c" : "a")\(female ? "f" : "m")h\(hair)d\(Figure3D.detail)"
    }

    private func family(_ key: String, look: Look, child: Bool, female: Bool, kind: AnimeArt.Figure, lite: Bool) -> Family {
        if let f = families[key] { return f }
        let f = Family()
        var s = AnimeRigs.standIn; s.style = look.style       // (any style of the family: the same hair)
        let rec = SwatchBook(recording: true)
        _ = Figure3D.anime(s, frame: 0, held: "", child: child, female: female, kind: kind, lite: lite, book: rec)
        f.standInCalls = rec.calls ?? []
        _ = Figure3D.anime(s, frame: 0, held: "", child: child, female: female, kind: kind, lite: lite, book: f.book)
        families[key] = f
        return f
    }

    /// The shared model of a shape: its key (for a cache) and, when asked, the model (inked when `ink` is given).
    public func shape(_ look: Look, frame: Int, held: String, child: Bool, female: Bool, kind: AnimeArt.Figure, lite: Bool, ink: Float?, build: Bool = true) -> (key: String, mesh: Mesh3D?)? {
        guard let fk = AnimeRigs.family(look, child: child, female: female, kind: kind, lite: lite) else { return nil }
        let key = "rig:\(fk):\(frame):\(held)"
        guard build else { return (key, nil) }
        let f = family(fk, look: look, child: child, female: female, kind: kind, lite: lite)
        var s = AnimeRigs.standIn; s.style = look.style
        var m = Figure3D.anime(s, frame: frame, held: held, child: child, female: female, kind: kind, lite: lite, book: f.book)
        if f.book.overflow { return nil }
        if let w = ink { m = m.inked(width: w) }
        return (key, m)
    }

    /// A person's own colours for their family's models, by column (nil when they cannot share the models).
    /// `columns` is how many columns the family's book had when the strip was made (a strip is remade when a
    /// new tool or step brings a new colour).
    public func swatches(_ look: Look, child: Bool, female: Bool, kind: AnimeArt.Figure, lite: Bool) -> (colors: [RGBA], columns: Int)? {
        guard let fk = AnimeRigs.family(look, child: child, female: female, kind: kind, lite: lite) else { return nil }
        let f = family(fk, look: look, child: child, female: female, kind: kind, lite: lite)
        let rec = SwatchBook(recording: true)
        _ = Figure3D.anime(look, frame: 0, held: "", child: child, female: female, kind: kind, lite: lite, book: rec)
        guard let mine = rec.calls, mine.count == f.standInCalls.count, !f.book.overflow else { return nil }
        var colors = f.book.bases            // colours no look changes (a tool, the ink, a ribbon) stay as they are
        var set = [Bool](repeating: false, count: colors.count)
        for (i, c) in f.standInCalls.enumerated() {
            guard let col = f.book.column(of: c) else { return nil }
            if set[col] { if colors[col] != mine[i] { return nil } } else { colors[col] = mine[i]; set[col] = true }
        }
        return (colors, colors.count)
    }

    /// How many columns a family's book has now.
    public func columns(_ look: Look, child: Bool, female: Bool, kind: AnimeArt.Figure, lite: Bool) -> Int {
        guard let fk = AnimeRigs.family(look, child: child, female: female, kind: kind, lite: lite) else { return 0 }
        return families[fk]?.book.bases.count ?? 0
    }
}
