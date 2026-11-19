import Foundation

// What can get there (world warfare task book, sections 4 and 5): a fleet lifts so much, a port takes in so
// much a round, and the smaller of the two is what lands. Four first technologies change these numbers:
//
//   railways          铁路       (the existing "railways"): land moves 1.5 times as much to a front
//   port expansion    港口扩建   (the existing "naval_eng"): every port takes in twice as much
//   ocean shipping    远洋运输   (the existing "deep_yard"): every shipyard's fleet lifts 2.5 times as much
//   mountain works    山地工程   (the existing "machining" with "steel"): passes no longer slow a supply train
//
// The numbers are in `WarBalance` (lift and intake per round); the research panel shows what each would change
// and the bottleneck now ("the fleet can carry 10,000; this port can take only 6,000 this round").

extension WarBalance {
    public static let firstTechs: [(key: String, en: String, zh: String)] = [
        ("railways", "Railways", "铁路"), ("naval_eng", "Port expansion", "港口扩建"),
        ("deep_yard", "Ocean shipping", "远洋运输"), ("machining", "Mountain works", "山地工程"),
    ]
}

extension Civ {
    /// What a nation's fleet can carry in one round (strength points): each city with a shipyard lifts
    /// `liftPerYard`, two and a half times that with ocean shipping. Nothing without a shipyard.
    public func fleetLift(_ n: Int) -> Double {
        let yards = cities(of: n).reduce(0) { $0 + min(1, $1.has("shipyard") + $1.has("deep_yard")) }
        return Double(yards) * cfg.war.liftPerYard * (knows(n, "deep_yard") ? 2.5 : 1)
    }

    /// What a port can take in one round (strength points): `intakePerPort`, twice that once its nation has
    /// expanded its ports, and more for a shipyard on the quay. Nil when the city is no port.
    public func portIntake(_ c: CivCity) -> Double? {
        guard portSite(c.regionKey, bodies: waterBodies()) != nil else { return nil }
        let base = cfg.war.intakePerPort * (knows(c.nation, "naval_eng") ? 2 : 1)
        return base + (c.has("shipyard") > 0 ? cfg.war.intakePerPort * 0.5 : 0)
    }

    /// What lands in one round when `attacker` comes by sea to the place `c`: the smaller of what its fleet lifts
    /// and what the port there takes in (a landing on an open shore takes in half a port). The port's intake
    /// counts whoever holds it: a port in enemy hands takes in nobody.
    public func landingRound(_ attacker: Int, at c: CivCity) -> (lands: Double, lift: Double, intake: Double) {
        let lift = fleetLift(attacker)
        let intake: Double
        if let p = portIntake(c) { intake = c.nation == attacker ? p : p * 0.5 }   // storming a quay from the boats
        else { intake = cfg.war.intakePerPort * 0.5 }
        return (min(lift, intake), lift, intake)
    }

    /// The research panel's line: what lands now, and what holds it back.
    public func bottleneck(_ attacker: Int, at c: CivCity, zh: Bool) -> String {
        let r = landingRound(attacker, at: c)
        let name = c.name(zh: zh)
        if r.lift <= 0 { return zh ? "没有船队：需要船厂" : "no fleet: it needs a shipyard" }
        if r.lift > r.intake {
            return zh ? String(format: "船队可运 %.0f，%@本轮只能接收 %.0f（港口是瓶颈：港口扩建可翻倍）", r.lift, name, r.intake)
                      : String(format: "the fleet can carry %.0f; %@ can take only %.0f this round (the port is the bottleneck: port expansion doubles it)", r.lift, name, r.intake)
        }
        return zh ? String(format: "船队可运 %.0f，%@本轮可接收 %.0f（船队是瓶颈：远洋运输 ×2.5）", r.lift, name, r.intake)
                  : String(format: "the fleet can carry %.0f; %@ can take %.0f this round (the fleet is the bottleneck: ocean shipping x2.5)", r.lift, name, r.intake)
    }

    /// What each first technology would change for a nation, in a line each (known ones are marked).
    public func techPreview(_ n: Int, zh: Bool) -> [String] {
        WarBalance.firstTechs.map { t in
            let has = knows(n, t.key)
            let what: String
            switch t.key {
            case "railways": what = zh ? "陆路前线运量 ×1.5" : "land moves 1.5x to a front"
            case "naval_eng": what = zh ? "每座港口每轮接收量 ×2" : "every port takes in 2x a round"
            case "deep_yard": what = zh ? "每座船厂的船队运量 ×2.5" : "each shipyard's fleet lifts 2.5x"
            default: what = zh ? "补给车队过山口不再减速" : "supply trains cross passes at full speed"
            }
            return (has ? "✓ " : "· ") + (zh ? t.zh : t.en) + "：" + what
        }
    }
}
