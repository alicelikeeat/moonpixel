import Foundation

// Services every mode uses. The open world, the civilisation layer, metro and command mode keep their
// own rules, but goods change hands and blows land in one place each, so the same check is made the
// same way everywhere and no mode has a second, slightly different way to spend or to hurt.

/// Somewhere goods are kept: a town's store, the traveller's pack, a city of the regional layer, a side
/// in command mode. Only what is free may be taken (goods held aside for something else are not).
public struct Holding {
    public let name: String
    public let free: (String) -> Double
    public let change: (String, Double) -> Void
    public init(_ name: String, free: @escaping (String) -> Double, change: @escaping (String, Double) -> Void) { self.name = name; self.free = free; self.change = change }
}

public enum Goods {
    /// Take all of these, or none: the first thing missing is named and nothing is taken.
    @discardableResult public static func take(_ want: [(String, Double)], from h: Holding) -> String? {
        let need = want.reduce(into: [String: Double]()) { $0[$1.0, default: 0] += $1.1 }
        for k in need.keys.sorted() where h.free(k) + 1e-9 < need[k]! { return k }
        for k in need.keys.sorted() { h.change(k, -need[k]!) }
        return nil
    }
    public static func take(_ want: [String: Double], from h: Holding) -> String? { take(want.map { ($0.key, $0.value) }, from: h) }

    /// Move goods from one holding to another, all or none.
    @discardableResult public static func move(_ goods: [(String, Double)], from a: Holding, to b: Holding) -> String? {
        if let lack = take(goods, from: a) { return lack }
        for (k, v) in goods { b.change(k, v) }
        return nil
    }
}

public enum Combat {
    /// One blow: what the weapon does, times its multiplier against the target's class of armour, times
    /// how well it was aimed (hunger, morale, a broken sight). The same in every mode.
    public static func damage(_ base: Double, vs: [Double], armor: Int, aim: Double = 1) -> Double {
        guard !vs.isEmpty else { return base * aim }
        return base * vs[min(vs.count - 1, max(0, armor))] * max(0, aim)
    }

    /// What a hit does to one key part of a large machine (1 whole ... 0 knocked out).
    public static func wear(part: Double, hit: Double, hp: Double, factor: Double = 3) -> Double {
        max(0, part - hit / max(1, hp) * factor)
    }
}

// MARK: - the holdings of each mode

extension CivCity {
    public var holding: Holding {
        Holding("city \(nameEn)", free: { [unowned self] in self.free($0) }, change: { [unowned self] k, v in self.stock[k, default: 0] += v })
    }
}

extension Settlement {
    public var holding: Holding { Holding("town \(nameEn)", free: { [unowned self] in self.good($0) }, change: { [unowned self] k, v in self.addGood(k, v) }) }
}

extension Society {
    /// The traveller's pack.
    public var pack: Holding { Holding("pack", free: { [unowned self] in self.carried($0) }, change: { [unowned self] k, v in self.carry(k, v) }) }
}

extension Skirmish {
    /// A side's war chest (moonstone is its only good).
    public func chest(_ side: Int) -> Holding {
        Holding("side \(side)", free: { [unowned self] k in k == "credits" ? self.sides[side].credits : 0 },
                change: { [unowned self] k, v in if k == "credits" { self.sides[side].credits += v } })
    }
}
