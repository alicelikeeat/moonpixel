import Foundation

// Flying from anywhere: the traveller picks another city's airport, goes to the nearest airport, and a charter
// plane (a turboprop bought by that airport's town, its goods and fuel taken from the town's store like any
// plane it buys) stands ready on the runway with that airport as its goal. As a passenger the autopilot flies
// the whole way: taxi, line up, take off, cruise, the approach down the centre line, landing. As the pilot one
// flies it by hand, and can hand it to the autopilot at any moment.

extension Society {
    /// Passenger airports (one stop each: the passenger end of each airport), by name.
    public func passengerAirports() -> [Stop] {
        net.stops.filter { $0.kind == .airport && !$0.name.contains("Cargo") && !$0.name.contains("货运") }
            .sorted { $0.name != $1.name ? $0.name < $1.name : $0.id < $1.id }
    }

    /// The passenger airport nearest a tile.
    public func nearestAirport(to t: TilePos) -> Stop? {
        passengerAirports().min { $0.tile.distance2(t) != $1.tile.distance2(t) ? $0.tile.distance2(t) < $1.tile.distance2(t) : $0.id < $1.id }
    }

    /// A charter flight from the airport nearest the traveller to `dest`: the plane is bought and made ready on
    /// the runway, the traveller is put aboard (at the controls when `pilot`). Returns the plane, or why not.
    @discardableResult public func charterFlight(to dest: Stop, pilot: Bool) -> (plane: Vehicle?, why: String?) {
        guard let me = realm.player.body, me.vehicle == nil else { return (nil, "already aboard") }
        guard let from = nearestAirport(to: me.pos.tile) else { return (nil, "no airport") }
        guard from.id != dest.id, from.tile.distance2(dest.tile) > 60 * 60 else { return (nil, "already there") }
        guard let d = from.district.flatMap({ id in net.districts.first { $0.id == id } }) else { return (nil, "no airport") }
        // a free place on the runway by the stop (another plane may be standing on the stop itself)
        var spot: TilePos?
        search: for r in 0...8 { for dy in -r...r { for dx in -r...r where max(abs(dx), abs(dy)) == r {
            let t = TilePos(from.tile.x + dx, from.tile.y + dy)
            if wayKind(at: t) == .runway && !net.vehicles.contains(where: { $0.kind.mode == .air && $0.tile.distance2(t) < 9 }) { spot = t; break search }
        } } }
        guard let at = spot else { return (nil, "the runway is busy") }
        buyShortfall(d, VehicleKind.turboprop.spec.build, keep: 0)
        guard let v = buildVehicle(.turboprop, at: at, heading: runwayAxis(at: at), payer: .district(d.id), nation: d.nation) else { return (nil, "no plane could be had") }
        v.name = (zh ? "包机 → " : "Charter → ") + dest.name
        v.task.goal = NetNode(dest.tile.x, dest.tile.y, 0)
        handOver(v, to: .auto)
        // the traveller walks out to it and climbs aboard
        var b = me
        b.x = v.pos.x; b.y = v.pos.y; b.depth = 0
        realm.player.body = b
        realm.player.depth = 0
        if let why = board(v.id, drive: pilot) { return (v, why) }
        if pilot { handOver(v, to: .manual) }
        return (v, nil)
    }
}
