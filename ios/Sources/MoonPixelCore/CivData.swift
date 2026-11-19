import Foundation

// Tables for the civilisation layer (Civ.swift): time, people, food, technology, industry and arms.
// Every rate here is a game-balance value in game time, not a claim about the real world.
//
// Time. The civilisation layer steps once per game hour (`Society.hour`, 50 s of play). A civ day is
// 24 steps (`MP.daySeconds`); a civ year is `CivConfig.daysPerYear` civ days. Rates are given per day
// unless the name says otherwise.

public struct CivConfig: Codable, Equatable {
    public var daysPerYear = 8.0
    // --- people
    public var childYears = 4.0, adultYears = 10.0            // years spent as a child, as a working adult
    public var fertility = 0.5                                // births per adult couple per year, before modifiers
    public var wealthDamp = 0.25                              // fertility / (1 + wealthDamp * wealth): richer is not endlessly more
    public var deathPerYear = [0.012, 0.006, 0.2]             // natural deaths per person-year: child, adult, elder
    public var careCut = 0.45                                 // share of natural and illness deaths a full clinic network prevents
    public var sickPerDay = 0.004, sickCrowd = 0.02, sickThirst = 0.03, sickHunger = 0.01
    public var sickRecover = 0.18, sickDeath = 0.012
    public var need = [0.6, 1.0, 0.8]                         // nutrition a day (1 = one adult's day): child, adult, elder
    public var needLabour = 0.2, needSoldier = 0.3, needCrew = 0.15
    // hunger: 0 fed, 1 peckish, 2 hungry, 3 starving, 4 famine-weak, 5 dying (see CivHunger)
    public var fedAbove = 0.95, hungryBelow = 0.8             // hysteresis: recover only above, worsen only below
    public var emergencyShare = 0.85                          // emergency rations: inside the dead band, so people stay peckish
    public var worsenPerDay = 0.5                             // share of a state that moves one step worse per day at total want
    public var recoverPerDay = 0.5                            // share of a state that moves one step better per fed day
    public var starveDeath = [0.0, 0.0, 0.0, 0.0, 0.02, 0.12] // deaths per day by hunger state
    public var work = [1.0, 0.97, 0.85, 0.6, 0.35, 0.15]      // work done by hunger state (never zero: the hungry still forage)
    public var fertile = [1.0, 1.0, 0.8, 0.4, 0.1, 0.0]
    public var leave = [0.0, 0.0, 0.01, 0.05, 0.08, 0.05]       // share that sets out elsewhere per day, by hunger state
    public var crowdLeave = 0.01                              // per day per unit of crowding over 1
    public var forage = 0.25                                  // nutrition per hungry adult per day found off the land, whatever the stock
    // --- places
    public var regionTiles = 256                              // a region is 8 x 8 chunks
    // --- geography (Geography.swift)
    public var openSeaRegions = 4                             // a body of water this many regions or more is open sea
    public var claimRadius = 2                                // land within this many regions answers to the nearest city
    public var coastSearch = 8                                // how far out the coast rule surveys for a coast
    public var straitDetour = 6                               // regions longer round by sea than across: a strait
    public var passMountain = 0.3                             // mountain share that makes a way in a pass
    public var deltaIsles = 4, deltaWater = 0.2               // river regions with this much water that make a delta
    // --- envoys, vassals and wars for a place (Diplomacy.swift): every number in one table
    public var war = WarBalance()
    public var rulesVersion = 1
    public var cityStateChance = 0.22                         // of a region with fertile land, when first known
    public var housePeople = 6.0, wellWater = 40.0, riverWater = 400.0
    public var plotWorkers = 2.0                              // adults a farm plot needs
    public var plotYield = 72.0                               // grain a plot gives at harvest (6 days), before land and skill
    public var travelDaysPerRegion = 1.5
    public var convoyCarry = 400.0, convoyLossBlockade = 1.0, convoyLossHostile = 0.15
    // --- polity
    public var taxPerWorker = 0.05, upkeepPerSoldier = 0.04
    public var supplyReach = 3, supplyLoss = 0.3, armyForage = 0.35              // regions from a friendly city a force is fed over, and what the road costs
    public var foodPrice = 0.05                               // money per unit of nutrition bought from another nation
    public var rivalry = 0.003                                // a day, between crowded neighbours who do not trade
    public var unrestIdentity = 0.4, unrestHunger = 0.5, unrestDistance = 0.08, unrestDebt = 0.3, unrestCalm = 0.25
    public var secedeUnrest = 1.0, rebelMinPeople = 60
    public var exileToHistoryYears = 6.0, exileMinIdentity = 30
    public var federateRelation = 0.85, federateYears = 3.0
    public var submitFatigue = 0.7
    public var warPressure = 0.35, warChance = 0.25           // per year at full pressure, after weighing what war costs
    /// War only on a polity this many times weaker (nil in older saves: 3). Relations at peace warm a little each year.
    public var warGap: Double? = nil
    /// How much relations at peace warm in a year (nil in older saves: 0.1).
    public var peaceWarmth: Double? = nil
    public var policyDelayDays = 1.0
    // --- research and industry
    public var researchPerResearcher = 0.12, diffusion = 0.4, capturedKnowledge = 0.3, capturedCap = 0.6
    public var refund = 0.5, salvage = 0.4
    public init() {}
}

// MARK: - people

public enum CivBand: Int, CaseIterable, Codable { case child = 0, adult = 1, elder = 2 }

public enum CivHunger {
    public static let names = [("Fed", "饱足"), ("Peckish", "轻度饥饿"), ("Hungry", "明显饥饿"), ("Starving", "严重饥饿"), ("Famine-weak", "饥荒衰弱"), ("Dying", "濒死")]
    public static let count = 6
}

// MARK: - food

public struct CivFood: Codable, Equatable {
    public let key: String, en: String, zh: String
    public let nutrition: Double       // adult-days per unit
    public let shelfDays: Double       // a share 1/shelfDays of the stock spoils each day
    public let tech: String?           // needed to make it
    /// Everything of this kind the game knows: the built-in pack and any added content packs.
    public static var all: [CivFood] { ContentRegistry.shared.foods }
    public static var byKey: [String: CivFood] { ContentRegistry.shared.foodsByKey }
    /// The kinds that come with the game (the "moonpixel" content pack).
    static let builtin: [CivFood] = [
        CivFood(key: "grain", en: "Grain", zh: "谷物", nutrition: 1.0, shelfDays: 360, tech: nil),
        CivFood(key: "vegetable", en: "Vegetables", zh: "蔬菜", nutrition: 0.5, shelfDays: 12, tech: nil),
        CivFood(key: "meat", en: "Meat", zh: "肉", nutrition: 1.2, shelfDays: 6, tech: nil),
        CivFood(key: "milk", en: "Milk", zh: "奶", nutrition: 0.6, shelfDays: 3, tech: nil),
        CivFood(key: "fish", en: "Fish", zh: "鱼", nutrition: 1.0, shelfDays: 4, tech: nil),
        CivFood(key: "bread", en: "Bread", zh: "面包", nutrition: 1.25, shelfDays: 8, tech: nil),
        CivFood(key: "meal", en: "Cooked meals", zh: "熟食", nutrition: 1.5, shelfDays: 2, tech: nil),
        CivFood(key: "ration", en: "Field rations", zh: "便携口粮", nutrition: 2.0, shelfDays: 500, tech: "preserving"),
        CivFood(key: "hydro", en: "Greenhouse greens", zh: "温室蔬菜", nutrition: 0.6, shelfDays: 14, tech: "greenhouse"),
        CivFood(key: "synth", en: "Synthetic nutrition", zh: "合成营养", nutrition: 2.5, shelfDays: 900, tech: "synth_food"),
    ]
    public static func isFood(_ k: String) -> Bool { byKey[k] != nil }
    /// What is eaten first: what spoils soonest.
    public static var eatOrder: [String] { ContentRegistry.shared.eatOrder }
    static func eatOrder(_ all: [CivFood]) -> [String] { all.sorted { $0.shelfDays != $1.shelfDays ? $0.shelfDays < $1.shelfDays : $0.key < $1.key }.map { $0.key }  }
}

public enum CivRation: String, Codable, CaseIterable {
    case normal, emergency, childrenFirst, armyFirst
    public var label: (String, String) {
        switch self {
        case .normal: return ("Normal rations", "正常配给")
        case .emergency: return ("Emergency rations (85%)", "紧急限量（85%）")
        case .childrenFirst: return ("Children first", "儿童优先")
        case .armyFirst: return ("Army first", "军需优先")
        }
    }
}

// MARK: - technology

public struct CivTech: Codable, Equatable {
    public let key: String, en: String, zh: String
    public let branch: String          // agri, industry, info, land, naval, air, mecha, space
    public let era: Int                // 0 farming & crafts, 1 metal & machines, 2 industry, 3 electric, 4 information, 5 future (a label only)
    public let needs: [String]
    public let cost: Double            // research points
    public let lab: Int                // research facility level needed (0 none, 1 school, 2 institute, 3 laboratory)
    public static let eraNames = [("Farming & crafts", "农耕手工"), ("Metal & machines", "冶金机械"), ("Industry", "工业"), ("Electric age", "电气化"), ("Information age", "信息化"), ("Future", "未来科技")]
    /// Everything of this kind the game knows: the built-in pack and any added content packs.
    public static var all: [CivTech] { ContentRegistry.shared.techs }
    public static var byKey: [String: CivTech] { ContentRegistry.shared.techsByKey }
    /// The kinds that come with the game (the "moonpixel" content pack).
    static let builtin: [CivTech] = [
        CivTech(key: "farming", en: "Farming", zh: "农耕", branch: "agri", era: 0, needs: [], cost: 0, lab: 0),
        CivTech(key: "husbandry", en: "Animal husbandry", zh: "畜牧", branch: "agri", era: 0, needs: ["farming"], cost: 20, lab: 0),
        CivTech(key: "fishing", en: "Fishing boats", zh: "渔船", branch: "naval", era: 0, needs: ["farming"], cost: 20, lab: 0),
        CivTech(key: "irrigation", en: "Irrigation", zh: "灌溉", branch: "agri", era: 0, needs: ["farming"], cost: 40, lab: 0),
        CivTech(key: "writing", en: "Writing & schools", zh: "文字与学堂", branch: "info", era: 0, needs: [], cost: 30, lab: 0),
        CivTech(key: "metallurgy", en: "Metallurgy", zh: "冶金", branch: "industry", era: 1, needs: ["writing"], cost: 60, lab: 1),
        CivTech(key: "preserving", en: "Preserving", zh: "食物保存", branch: "agri", era: 1, needs: ["husbandry"], cost: 50, lab: 1),
        CivTech(key: "machining", en: "Machining", zh: "机械加工", branch: "industry", era: 1, needs: ["metallurgy"], cost: 90, lab: 1),
        CivTech(key: "rotation", en: "Crop rotation", zh: "轮作", branch: "agri", era: 1, needs: ["irrigation"], cost: 70, lab: 1),
        CivTech(key: "medicine", en: "Medicine", zh: "医学", branch: "info", era: 1, needs: ["writing"], cost: 80, lab: 1),
        CivTech(key: "steam", en: "Steam power", zh: "蒸汽动力", branch: "industry", era: 2, needs: ["machining"], cost: 140, lab: 2),
        CivTech(key: "steel", en: "Steel", zh: "钢铁", branch: "industry", era: 2, needs: ["machining"], cost: 150, lab: 2),
        CivTech(key: "rifles", en: "Rifles", zh: "步枪", branch: "land", era: 2, needs: ["steel"], cost: 120, lab: 2),
        CivTech(key: "fertilizer", en: "Fertilizer", zh: "化肥", branch: "agri", era: 2, needs: ["rotation", "steam"], cost: 160, lab: 2),
        CivTech(key: "railways", en: "Railways", zh: "铁路", branch: "industry", era: 2, needs: ["steam", "steel"], cost: 180, lab: 2),
        CivTech(key: "naval_eng", en: "Naval engineering", zh: "造船工程", branch: "naval", era: 2, needs: ["steel", "fishing"], cost: 180, lab: 2),
        CivTech(key: "electricity", en: "Electricity", zh: "电力", branch: "industry", era: 3, needs: ["steam"], cost: 260, lab: 2),
        CivTech(key: "oil", en: "Oil refining", zh: "石油炼化", branch: "industry", era: 3, needs: ["steam"], cost: 240, lab: 2),
        CivTech(key: "engines", en: "Motor engines", zh: "内燃机", branch: "land", era: 3, needs: ["oil", "machining"], cost: 260, lab: 2),
        CivTech(key: "artillery", en: "Modern artillery", zh: "现代火炮", branch: "land", era: 3, needs: ["rifles", "engines"], cost: 260, lab: 2),
        CivTech(key: "cold_chain", en: "Cold chain", zh: "冷链", branch: "agri", era: 3, needs: ["electricity", "preserving"], cost: 220, lab: 2),
        CivTech(key: "flight", en: "Powered flight", zh: "动力飞行", branch: "air", era: 3, needs: ["engines"], cost: 320, lab: 3),
        CivTech(key: "radio", en: "Radio & radar", zh: "无线电与雷达", branch: "info", era: 3, needs: ["electricity"], cost: 300, lab: 3),
        CivTech(key: "deep_yard", en: "Deep-water shipyards", zh: "深水船坞", branch: "naval", era: 3, needs: ["naval_eng", "electricity"], cost: 360, lab: 3),
        CivTech(key: "electronics", en: "Electronics", zh: "电子学", branch: "info", era: 4, needs: ["radio"], cost: 420, lab: 3),
        CivTech(key: "greenhouse", en: "Greenhouses & hydroponics", zh: "温室水培", branch: "agri", era: 4, needs: ["fertilizer", "electricity"], cost: 380, lab: 3),
        CivTech(key: "missiles", en: "Guided missiles", zh: "制导导弹", branch: "land", era: 4, needs: ["artillery", "electronics"], cost: 480, lab: 3),
        CivTech(key: "jets", en: "Jet aircraft", zh: "喷气式飞机", branch: "air", era: 4, needs: ["flight", "electronics"], cost: 500, lab: 3),
        CivTech(key: "carrier_ops", en: "Carrier operations", zh: "舰载航空", branch: "naval", era: 4, needs: ["deep_yard", "jets"], cost: 560, lab: 3),
        CivTech(key: "drones", en: "Drones", zh: "无人机", branch: "air", era: 4, needs: ["electronics", "flight"], cost: 440, lab: 3),
        CivTech(key: "computing", en: "Computing", zh: "计算机", branch: "info", era: 4, needs: ["electronics"], cost: 520, lab: 3),
        CivTech(key: "robotics", en: "Robotics", zh: "机器人学", branch: "industry", era: 4, needs: ["computing", "engines"], cost: 600, lab: 3),
        CivTech(key: "auto_farm", en: "Automated farms", zh: "自动农场", branch: "agri", era: 5, needs: ["robotics", "greenhouse"], cost: 700, lab: 3),
        CivTech(key: "frame", en: "Heavy humanoid frames", zh: "重型人形机体", branch: "mecha", era: 5, needs: ["robotics", "missiles"], cost: 820, lab: 3),
        CivTech(key: "fusion", en: "Compact fusion", zh: "紧凑聚变", branch: "industry", era: 5, needs: ["computing", "electricity"], cost: 900, lab: 3),
        CivTech(key: "frame_reactor", en: "Frame reactors", zh: "机体反应堆", branch: "mecha", era: 5, needs: ["frame", "fusion"], cost: 900, lab: 3),
        CivTech(key: "synth_food", en: "Synthetic nutrition", zh: "合成营养", branch: "agri", era: 5, needs: ["auto_farm", "fusion"], cost: 860, lab: 3),
        CivTech(key: "aerospace", en: "Aerospace hulls", zh: "空天船体", branch: "space", era: 5, needs: ["jets", "fusion"], cost: 1000, lab: 3),
        CivTech(key: "lift", en: "Field lift", zh: "场升力", branch: "space", era: 5, needs: ["aerospace", "frame_reactor"], cost: 1200, lab: 3),
    ]
}

// MARK: - industry

public struct CivItem: Codable, Equatable {
    public let key: String, en: String, zh: String
    /// Everything of this kind the game knows: the built-in pack and any added content packs.
    public static var all: [CivItem] { ContentRegistry.shared.items }
    public static var byKey: [String: CivItem] { ContentRegistry.shared.itemsByKey }
    /// The kinds that come with the game (the "moonpixel" content pack).
    static let builtin: [CivItem] = [
        CivItem(key: "timber", en: "Timber", zh: "木材"), CivItem(key: "stone", en: "Stone", zh: "石料"),
        CivItem(key: "ore", en: "Iron ore", zh: "铁矿石"), CivItem(key: "coal", en: "Coal", zh: "煤"), CivItem(key: "crude", en: "Crude oil", zh: "原油"),
        CivItem(key: "steel", en: "Steel", zh: "钢材"), CivItem(key: "fuel", en: "Fuel", zh: "燃料"),
        CivItem(key: "parts", en: "Machine parts", zh: "机械部件"), CivItem(key: "electronics", en: "Electronics", zh: "电子元件"),
        CivItem(key: "armor", en: "Armour plate", zh: "装甲板"), CivItem(key: "engine", en: "Engines", zh: "发动机"),
        CivItem(key: "weapons", en: "Weapon systems", zh: "武器系统"), CivItem(key: "core", en: "Reactor cores", zh: "反应堆芯"),
        CivItem(key: "ammo", en: "Ammunition", zh: "弹药"),
    ]
    public static func name(_ k: String, zh: Bool) -> String {
        if let i = byKey[k] { return zh ? i.zh : i.en }
        if let f = CivFood.byKey[k] { return zh ? f.zh : f.en }
        return k
    }
}

/// Places a city builds. Workers come from its adults; energy from its power plants.
public struct CivFacility: Codable, Equatable {
    public let key: String, en: String, zh: String
    public let tech: String?
    public let cost: [String: Double]  // materials to build
    public let workers: Int
    public let energy: Double          // made (+) or used (-) per day
    public let needs: String?          // terrain: "coast", "deep" (deep water), nil anywhere
    /// Everything of this kind the game knows: the built-in pack and any added content packs.
    public static var all: [CivFacility] { ContentRegistry.shared.facilities }
    public static var byKey: [String: CivFacility] { ContentRegistry.shared.facilitiesByKey }
    /// The kinds that come with the game (the "moonpixel" content pack).
    static let builtin: [CivFacility] = [
        CivFacility(key: "house", en: "Housing", zh: "住房", tech: nil, cost: ["timber": 10, "stone": 5], workers: 0, energy: 0, needs: nil),
        CivFacility(key: "farm", en: "Farm plots", zh: "农田", tech: nil, cost: ["timber": 6], workers: 2, energy: 0, needs: nil),
        CivFacility(key: "pasture", en: "Pasture", zh: "牧场", tech: "husbandry", cost: ["timber": 10], workers: 2, energy: 0, needs: nil),
        CivFacility(key: "fishery", en: "Fishery", zh: "渔场", tech: "fishing", cost: ["timber": 12], workers: 3, energy: 0, needs: "coast"),
        CivFacility(key: "well", en: "Wells & cisterns", zh: "水井蓄水", tech: nil, cost: ["stone": 12], workers: 0, energy: 0, needs: nil),
        CivFacility(key: "granary", en: "Granary", zh: "粮仓", tech: nil, cost: ["timber": 20, "stone": 20], workers: 1, energy: 0, needs: nil),
        CivFacility(key: "bakery", en: "Bakery & kitchen", zh: "面包房与厨房", tech: nil, cost: ["stone": 15, "timber": 10], workers: 3, energy: 0, needs: nil),
        CivFacility(key: "clinic", en: "Clinic", zh: "诊所", tech: "medicine", cost: ["stone": 20, "timber": 10], workers: 2, energy: 0, needs: nil),
        CivFacility(key: "school", en: "School", zh: "学校", tech: "writing", cost: ["stone": 15, "timber": 15], workers: 2, energy: 0, needs: nil),
        CivFacility(key: "institute", en: "Institute", zh: "研究院", tech: "metallurgy", cost: ["stone": 40, "timber": 30], workers: 6, energy: -1, needs: nil),
        CivFacility(key: "laboratory", en: "Laboratory", zh: "实验室", tech: "electricity", cost: ["steel": 30, "parts": 10], workers: 8, energy: -4, needs: nil),
        CivFacility(key: "mine", en: "Mine", zh: "矿井", tech: "metallurgy", cost: ["timber": 20], workers: 6, energy: 0, needs: nil),
        CivFacility(key: "oilwell", en: "Oil well", zh: "油井", tech: "oil", cost: ["steel": 12], workers: 4, energy: -1, needs: nil),
        CivFacility(key: "steelworks", en: "Steelworks", zh: "钢铁厂", tech: "steel", cost: ["stone": 40, "timber": 20], workers: 10, energy: -2, needs: nil),
        CivFacility(key: "refinery", en: "Refinery", zh: "炼油厂", tech: "oil", cost: ["steel": 30], workers: 6, energy: -2, needs: nil),
        CivFacility(key: "factory", en: "Factory", zh: "工厂", tech: "machining", cost: ["stone": 30, "timber": 20], workers: 10, energy: -2, needs: nil),
        CivFacility(key: "fab", en: "Electronics fab", zh: "电子厂", tech: "electronics", cost: ["steel": 30, "parts": 20], workers: 10, energy: -5, needs: nil),
        CivFacility(key: "plant", en: "Power plant", zh: "发电厂", tech: "electricity", cost: ["steel": 25, "stone": 20], workers: 5, energy: 30, needs: nil),
        CivFacility(key: "fusion_plant", en: "Fusion plant", zh: "聚变电站", tech: "fusion", cost: ["steel": 60, "electronics": 30, "core": 2], workers: 8, energy: 200, needs: nil),
        CivFacility(key: "greenhouse", en: "Greenhouse", zh: "温室", tech: "greenhouse", cost: ["steel": 10, "parts": 6], workers: 2, energy: -2, needs: nil),
        CivFacility(key: "autofarm", en: "Automated farm", zh: "自动农场", tech: "auto_farm", cost: ["steel": 20, "electronics": 10], workers: 1, energy: -6, needs: nil),
        CivFacility(key: "synth_plant", en: "Nutrition plant", zh: "合成营养厂", tech: "synth_food", cost: ["steel": 30, "electronics": 20], workers: 4, energy: -20, needs: nil),
        CivFacility(key: "ration_works", en: "Ration works", zh: "口粮厂", tech: "preserving", cost: ["stone": 20, "timber": 10], workers: 4, energy: 0, needs: nil),
        CivFacility(key: "barracks", en: "Barracks", zh: "兵营", tech: nil, cost: ["timber": 20, "stone": 20], workers: 2, energy: 0, needs: nil),
        CivFacility(key: "motor_works", en: "Motor works", zh: "车辆厂", tech: "engines", cost: ["steel": 40, "parts": 20], workers: 12, energy: -4, needs: nil),
        CivFacility(key: "shipyard", en: "Shipyard", zh: "船厂", tech: "naval_eng", cost: ["steel": 40, "timber": 40], workers: 14, energy: -3, needs: "coast"),
        CivFacility(key: "deep_yard", en: "Deep-water dockyard", zh: "深水船坞", tech: "deep_yard", cost: ["steel": 120, "parts": 40], workers: 30, energy: -10, needs: "deep"),
        CivFacility(key: "airfield", en: "Airfield", zh: "机场", tech: "flight", cost: ["stone": 60, "steel": 20], workers: 8, energy: -2, needs: nil),
        CivFacility(key: "aircraft_works", en: "Aircraft works", zh: "飞机厂", tech: "flight", cost: ["steel": 60, "parts": 30], workers: 14, energy: -6, needs: nil),
        CivFacility(key: "frame_works", en: "Frame works", zh: "机体工厂", tech: "frame", cost: ["steel": 120, "electronics": 40, "parts": 40], workers: 24, energy: -20, needs: nil),
        CivFacility(key: "sky_yard", en: "Sky dock", zh: "空天船坞", tech: "aerospace", cost: ["steel": 300, "electronics": 120, "core": 4], workers: 60, energy: -60, needs: nil),
    ]
}

/// One way of turning things into other things in a facility: inputs, outputs, hours of work by its crew, energy.
public struct CivRecipe: Codable, Equatable {
    public let key: String, facility: String
    public let inputs: [String: Double], outputs: [String: Double]
    public let hours: Double, energy: Double
    public let tech: String?
    /// Everything of this kind the game knows: the built-in pack and any added content packs.
    public static var all: [CivRecipe] { ContentRegistry.shared.recipes }
    public static var byKey: [String: CivRecipe] { ContentRegistry.shared.recipesByKey }
    /// The kinds that come with the game (the "moonpixel" content pack).
    static let builtin: [CivRecipe] = [
        CivRecipe(key: "bread", facility: "bakery", inputs: ["grain": 4], outputs: ["bread": 4], hours: 4, energy: 0, tech: nil),
        CivRecipe(key: "meal", facility: "bakery", inputs: ["vegetable": 2, "meat": 1, "grain": 1], outputs: ["meal": 4], hours: 4, energy: 0, tech: nil),
        CivRecipe(key: "ration", facility: "ration_works", inputs: ["grain": 4, "meat": 2], outputs: ["ration": 4], hours: 6, energy: 0, tech: "preserving"),
        CivRecipe(key: "synth", facility: "synth_plant", inputs: ["grain": 2], outputs: ["synth": 6], hours: 6, energy: 4, tech: "synth_food"),
        CivRecipe(key: "steel", facility: "steelworks", inputs: ["ore": 2, "coal": 1], outputs: ["steel": 1], hours: 4, energy: 1, tech: "steel"),
        CivRecipe(key: "fuel", facility: "refinery", inputs: ["crude": 2], outputs: ["fuel": 1.5], hours: 3, energy: 1, tech: "oil"),
        CivRecipe(key: "parts", facility: "factory", inputs: ["steel": 1], outputs: ["parts": 2], hours: 4, energy: 1, tech: "machining"),
        CivRecipe(key: "armor", facility: "factory", inputs: ["steel": 3], outputs: ["armor": 1], hours: 6, energy: 2, tech: "steel"),
        CivRecipe(key: "engine", facility: "factory", inputs: ["parts": 2, "steel": 1], outputs: ["engine": 1], hours: 8, energy: 2, tech: "engines"),
        CivRecipe(key: "ammo", facility: "factory", inputs: ["steel": 1, "coal": 1], outputs: ["ammo": 4], hours: 3, energy: 1, tech: "rifles"),
        CivRecipe(key: "electronics", facility: "fab", inputs: ["parts": 1, "steel": 0.5], outputs: ["electronics": 1], hours: 6, energy: 4, tech: "electronics"),
        CivRecipe(key: "weapons", facility: "factory", inputs: ["steel": 1, "parts": 1, "electronics": 0.5], outputs: ["weapons": 1], hours: 8, energy: 2, tech: "missiles"),
        CivRecipe(key: "core", facility: "fab", inputs: ["electronics": 3, "steel": 3], outputs: ["core": 1], hours: 24, energy: 20, tech: "fusion"),
    ]
}

// MARK: - arms

/// The layers a battle has. A weapon names the layers it can reach; nothing else can be hit by it.
public enum CivLayer: Int, Codable, CaseIterable { case ground = 0, sea, underwater, lowAir, highAir, nearSpace
    public var label: (String, String) {
        [("ground", "地面"), ("sea", "水面"), ("underwater", "水下"), ("low air", "低空"), ("high air", "高空"), ("near space", "近空间")][rawValue]
    }
    public var air: Bool { self == .lowAir || self == .highAir || self == .nearSpace }
}

/// How wide a passage a unit needs between regions: people go anywhere, a frame needs a real road or open land.
public enum CivSize: Int, Codable { case person = 0, vehicle, large, huge }

public struct CivWeapon: Codable, Equatable {
    public static var all: [CivWeapon] { ContentRegistry.shared.weapons }
    public static var byKey: [String: CivWeapon] { ContentRegistry.shared.weaponsByKey }
    public let key: String
    public let range: Int              // regions: 0 the same one, 1 a neighbour
    public let layers: Set<CivLayer>
    public let damage: Double
    public let vs: [Double]            // multiplier against armour 0 soft, 1 armoured, 2 heavy, 3 structure
    public let ammo: Double            // used per shot (0: energy weapon, uses energy instead)
    public let energy: Double
    public let cooldown: Double        // hours
    public let flight: Double          // hours from launch to impact (0: straight away)
    public let heat: Double
}

/// A machine (or a band of people) as a set of capabilities. A carrier is a platform that moves on the
/// sea + a hull + a crew + stores + a hangar bay + weapons; a sky carrier is the same with another
/// layer and a power draw instead of fuel. Only the capabilities a thing has are stored; the rules
/// ask "has it a hangar bay?", never "is this the carrier?".
public struct CivUnitDef: Codable, Equatable {
    public struct Build: Codable, Equatable { public var tech: [String]; public var facility: String; public var stages: [[String: Double]]; public var hours: Double }
    public struct Move: Codable, Equatable { public var layer: CivLayer; public var size: CivSize; public var speed: Double }
    public struct Tank: Codable, Equatable { public var cap: Double; public var perDay: Double }
    public struct Power: Codable, Equatable { public var perDay: Double }
    public struct Hull: Codable, Equatable { public var hp: Double; public var armor: Int; public var parts: [String] }
    public struct Crew: Codable, Equatable { public var people: Int; public var upkeep: Double }
    public struct Stores: Codable, Equatable { public var ammo: Double; public var food: Double }
    public struct Thermal: Codable, Equatable { public var cap: Double; public var cool: Double }
    public struct Sensor: Codable, Equatable { public var range: Int; public var stealth: Int }
    public struct HangarBay: Codable, Equatable { public var capacity: Int; public var deckPerHour: Int }
    public struct Flight: Codable, Equatable { public var carrierBased: Bool; public var endurance: Double }

    public var key: String, en: String, zh: String
    public var build: Build
    public var move: Move
    public var fuelTank: Tank?
    public var power: Power?
    public var hull: Hull
    public var crewing: Crew
    public var stores: Stores?
    public var thermal: Thermal?
    public var eyes: Sensor?
    public var weaponKeys: [String]
    public var hangarBay: HangarBay?
    public var flight: Flight?
    /// Picture used to draw it (checked against the art the game has).
    public var art: String?

    // the rules read capabilities through these
    public var layer: CivLayer { move.layer }
    public var size: CivSize { move.size }
    public var speed: Double { move.speed }
    public var tech: [String] { build.tech }
    public var facility: String { build.facility }
    public var stages: [[String: Double]] { build.stages }
    public var hours: Double { build.hours }
    public var crew: Int { crewing.people }
    public var upkeep: Double { crewing.upkeep }
    public var hp: Double { hull.hp }
    public var armor: Int { hull.armor }
    public var parts: [String] { hull.parts }
    public var fuelCap: Double { fuelTank?.cap ?? 0 }
    public var fuelPerDay: Double { fuelTank?.perDay ?? 0 }
    public var energyPerDay: Double { power?.perDay ?? 0 }
    public var ammoCap: Double { stores?.ammo ?? 0 }
    public var foodCap: Double { stores?.food ?? 0 }
    public var heatCap: Double { thermal?.cap ?? 0 }
    public var cool: Double { thermal?.cool ?? 0 }
    public var sensor: Int { eyes?.range ?? 0 }
    public var stealth: Int { eyes?.stealth ?? 0 }
    public var weapons: [CivWeapon] { ContentRegistry.shared.unitWeapons[key] ?? weaponKeys.compactMap { CivWeapon.byKey[$0] } }
    public var hangar: Int { hangarBay?.capacity ?? 0 }
    public var deckPerHour: Int { hangarBay?.deckPerHour ?? 0 }
    public var carrierBased: Bool { flight?.carrierBased ?? false }
    public var endurance: Double { flight?.endurance ?? 0 }
    public var label: String { key }

    public init(key: String, en: String, zh: String, build: Build, move: Move, fuelTank: Tank? = nil, power: Power? = nil, hull: Hull, crewing: Crew,
                stores: Stores? = nil, thermal: Thermal? = nil, eyes: Sensor? = nil, weaponKeys: [String] = [], hangarBay: HangarBay? = nil, flight: Flight? = nil, art: String? = nil) {
        self.key = key; self.en = en; self.zh = zh; self.build = build; self.move = move; self.fuelTank = fuelTank; self.power = power; self.hull = hull
        self.crewing = crewing; self.stores = stores; self.thermal = thermal; self.eyes = eyes; self.weaponKeys = weaponKeys; self.hangarBay = hangarBay; self.flight = flight; self.art = art
    }

    /// The built-in table is written flat; only the capabilities each one really has are kept.
    init(key: String, en: String, zh: String, layer: CivLayer, size: CivSize, tech: [String], facility: String, stages: [[String: Double]], hours: Double,
         crew: Int, upkeep: Double, hp: Double, armor: Int, speed: Double, fuelCap: Double, fuelPerDay: Double, energyPerDay: Double,
         ammoCap: Double, foodCap: Double, heatCap: Double, cool: Double, sensor: Int, stealth: Int, weapons: [CivWeapon],
         hangar: Int, deckPerHour: Int, carrierBased: Bool, endurance: Double, parts: [String]) {
        self.init(key: key, en: en, zh: zh, build: Build(tech: tech, facility: facility, stages: stages, hours: hours), move: Move(layer: layer, size: size, speed: speed),
                  fuelTank: fuelCap > 0 ? Tank(cap: fuelCap, perDay: fuelPerDay) : nil, power: energyPerDay > 0 ? Power(perDay: energyPerDay) : nil,
                  hull: Hull(hp: hp, armor: armor, parts: parts), crewing: Crew(people: crew, upkeep: upkeep),
                  stores: ammoCap > 0 || foodCap > 0 ? Stores(ammo: ammoCap, food: foodCap) : nil, thermal: heatCap > 0 ? Thermal(cap: heatCap, cool: cool) : nil,
                  eyes: sensor > 0 || stealth > 0 ? Sensor(range: sensor, stealth: stealth) : nil, weaponKeys: weapons.map { $0.key },
                  hangarBay: hangar > 0 ? HangarBay(capacity: hangar, deckPerHour: deckPerHour) : nil,
                  flight: carrierBased || endurance > 0 ? Flight(carrierBased: carrierBased, endurance: endurance) : nil, art: "civ:" + key)
    }

    static var builtinWeapons: [CivWeapon] { [spear, rifle, cannon, howitzer, sam, longSam, droneShot, airMissile, strike, torpedo, depth, naval, shipAA, beam, blade, antiFrame, skyBattery] }
    static let spear = CivWeapon(key: "spears", range: 0, layers: [.ground], damage: 2.5, vs: [1, 0.1, 0.02, 0.05], ammo: 0, energy: 0, cooldown: 1, flight: 0, heat: 0)
    static let rifle = CivWeapon(key: "rifle", range: 0, layers: [.ground, .lowAir], damage: 4, vs: [1, 0.15, 0.05, 0.1], ammo: 0.2, energy: 0, cooldown: 1, flight: 0, heat: 0)
    static let cannon = CivWeapon(key: "cannon", range: 0, layers: [.ground, .sea], damage: 20, vs: [0.8, 1, 0.5, 0.8], ammo: 1, energy: 0, cooldown: 1, flight: 0, heat: 0)
    static let howitzer = CivWeapon(key: "howitzer", range: 1, layers: [.ground, .sea], damage: 30, vs: [1, 0.7, 0.4, 1.2], ammo: 2, energy: 0, cooldown: 2, flight: 1, heat: 0)
    static let sam = CivWeapon(key: "sam", range: 1, layers: [.lowAir, .highAir], damage: 40, vs: [1, 1, 0.6, 0.3], ammo: 2, energy: 0, cooldown: 2, flight: 1, heat: 0)
    static let longSam = CivWeapon(key: "long_sam", range: 2, layers: [.highAir, .nearSpace], damage: 60, vs: [1, 1, 0.7, 0.4], ammo: 4, energy: 0, cooldown: 4, flight: 2, heat: 0)
    static let droneShot = CivWeapon(key: "drone_strike", range: 0, layers: [.ground, .sea], damage: 12, vs: [1, 0.6, 0.2, 0.5], ammo: 0.5, energy: 0, cooldown: 3, flight: 0, heat: 0)
    static let airMissile = CivWeapon(key: "air_missile", range: 1, layers: [.lowAir, .highAir], damage: 35, vs: [1, 1, 0.5, 0.2], ammo: 1, energy: 0, cooldown: 2, flight: 0, heat: 0)
    static let strike = CivWeapon(key: "strike", range: 0, layers: [.ground, .sea], damage: 45, vs: [1, 1, 0.6, 1.2], ammo: 2, energy: 0, cooldown: 3, flight: 0, heat: 0)
    static let torpedo = CivWeapon(key: "torpedo", range: 0, layers: [.sea, .underwater], damage: 80, vs: [1, 1, 1, 1], ammo: 2, energy: 0, cooldown: 3, flight: 1, heat: 0)
    static let depth = CivWeapon(key: "depth_charge", range: 0, layers: [.underwater], damage: 40, vs: [1, 1, 1, 1], ammo: 1, energy: 0, cooldown: 2, flight: 0, heat: 0)
    static let naval = CivWeapon(key: "naval_gun", range: 1, layers: [.sea, .ground], damage: 35, vs: [1, 1, 0.6, 1], ammo: 2, energy: 0, cooldown: 2, flight: 1, heat: 0)
    static let shipAA = CivWeapon(key: "ship_aa", range: 0, layers: [.lowAir, .highAir], damage: 22, vs: [1, 1, 0.5, 0.2], ammo: 1, energy: 0, cooldown: 1, flight: 0, heat: 0)
    static let beam = CivWeapon(key: "beam_rifle", range: 0, layers: [.ground, .sea, .lowAir], damage: 60, vs: [1, 1, 0.9, 1], ammo: 0, energy: 6, cooldown: 1, flight: 0, heat: 30)
    static let blade = CivWeapon(key: "heat_blade", range: 0, layers: [.ground], damage: 90, vs: [1, 1, 1.2, 1.5], ammo: 0, energy: 3, cooldown: 1, flight: 0, heat: 20)
    static let antiFrame = CivWeapon(key: "lance_missile", range: 0, layers: [.ground], damage: 70, vs: [0.3, 1, 1.4, 0.8], ammo: 2, energy: 0, cooldown: 2, flight: 0, heat: 0)
    static let skyBattery = CivWeapon(key: "sky_battery", range: 1, layers: [.ground, .sea, .lowAir, .highAir], damage: 40, vs: [1, 1, 0.8, 1], ammo: 0, energy: 20, cooldown: 3, flight: 0, heat: 40)

    public static var all: [CivUnitDef] { ContentRegistry.shared.units }
    public static var byKey: [String: CivUnitDef] { ContentRegistry.shared.unitsByKey }
    static let builtin: [CivUnitDef] = [
        CivUnitDef(key: "levy", en: "Levy band", zh: "民兵队", layer: .ground, size: .person, tech: [], facility: "barracks",
                   stages: [["timber": 10]], hours: 12, crew: 30, upkeep: 0.5, hp: 120, armor: 0, speed: 1.0, fuelCap: 0, fuelPerDay: 0, energyPerDay: 0,
                   ammoCap: 0, foodCap: 300, heatCap: 0, cool: 0, sensor: 0, stealth: 1, weapons: [spear], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: []),
        CivUnitDef(key: "infantry", en: "Rifle company", zh: "步兵连", layer: .ground, size: .person, tech: ["rifles"], facility: "barracks",
                   stages: [["steel": 2, "ammo": 10]], hours: 12, crew: 20, upkeep: 1, hp: 120, armor: 0, speed: 1.0, fuelCap: 0, fuelPerDay: 0, energyPerDay: 0,
                   ammoCap: 30, foodCap: 120, heatCap: 0, cool: 0, sensor: 0, stealth: 1, weapons: [rifle], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: []),
        CivUnitDef(key: "lancers", en: "Anti-frame company", zh: "反机甲连", layer: .ground, size: .person, tech: ["missiles"], facility: "barracks",
                   stages: [["weapons": 2, "ammo": 10]], hours: 16, crew: 16, upkeep: 1.5, hp: 100, armor: 0, speed: 1.0, fuelCap: 0, fuelPerDay: 0, energyPerDay: 0,
                   ammoCap: 24, foodCap: 100, heatCap: 0, cool: 0, sensor: 0, stealth: 1, weapons: [antiFrame, rifle], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: []),
        CivUnitDef(key: "armour", en: "Armoured troop", zh: "装甲车队", layer: .ground, size: .vehicle, tech: ["engines"], facility: "motor_works",
                   stages: [["steel": 10, "engine": 2], ["armor": 4, "parts": 4]], hours: 24, crew: 12, upkeep: 3, hp: 220, armor: 1, speed: 2.0, fuelCap: 40, fuelPerDay: 6, energyPerDay: 0,
                   ammoCap: 30, foodCap: 60, heatCap: 0, cool: 0, sensor: 0, stealth: 0, weapons: [cannon], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["power", "weapons"]),
        CivUnitDef(key: "artillery", en: "Artillery battery", zh: "炮兵连", layer: .ground, size: .vehicle, tech: ["artillery"], facility: "motor_works",
                   stages: [["steel": 12, "parts": 6], ["engine": 1, "ammo": 20]], hours: 24, crew: 14, upkeep: 3, hp: 120, armor: 0, speed: 1.2, fuelCap: 30, fuelPerDay: 4, energyPerDay: 0,
                   ammoCap: 60, foodCap: 70, heatCap: 0, cool: 0, sensor: 0, stealth: 0, weapons: [howitzer], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["weapons"]),
        CivUnitDef(key: "air_defence", en: "Air-defence battery", zh: "防空连", layer: .ground, size: .vehicle, tech: ["missiles", "radio"], facility: "motor_works",
                   stages: [["steel": 10, "electronics": 6], ["weapons": 3, "ammo": 20]], hours: 24, crew: 12, upkeep: 4, hp: 120, armor: 0, speed: 1.2, fuelCap: 30, fuelPerDay: 3, energyPerDay: 0,
                   ammoCap: 40, foodCap: 60, heatCap: 0, cool: 0, sensor: 2, stealth: 0, weapons: [sam, longSam], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["weapons", "control"]),
        CivUnitDef(key: "drone", en: "Drone flight", zh: "无人机编队", layer: .lowAir, size: .person, tech: ["drones"], facility: "aircraft_works",
                   stages: [["electronics": 4, "parts": 3]], hours: 12, crew: 0, upkeep: 1, hp: 30, armor: 0, speed: 6, fuelCap: 0, fuelPerDay: 0, energyPerDay: 0,
                   ammoCap: 6, foodCap: 0, heatCap: 0, cool: 0, sensor: 2, stealth: 2, weapons: [droneShot], hangar: 0, deckPerHour: 0, carrierBased: true, endurance: 8, parts: []),
        CivUnitDef(key: "fighter", en: "Strike fighter", zh: "攻击战斗机", layer: .highAir, size: .vehicle, tech: ["jets"], facility: "aircraft_works",
                   stages: [["steel": 8, "engine": 2], ["electronics": 6, "weapons": 2]], hours: 24, crew: 2, upkeep: 3, hp: 90, armor: 1, speed: 12, fuelCap: 20, fuelPerDay: 0, energyPerDay: 0,
                   ammoCap: 8, foodCap: 4, heatCap: 0, cool: 0, sensor: 2, stealth: 1, weapons: [airMissile, strike], hangar: 0, deckPerHour: 0, carrierBased: true, endurance: 10, parts: []),
        CivUnitDef(key: "escort", en: "Escort ship", zh: "护卫舰", layer: .sea, size: .huge, tech: ["naval_eng", "radio"], facility: "shipyard",
                   stages: [["steel": 40, "engine": 3], ["armor": 8, "weapons": 3, "electronics": 4]], hours: 48, crew: 80, upkeep: 6, hp: 500, armor: 2, speed: 3, fuelCap: 120, fuelPerDay: 10, energyPerDay: 0,
                   ammoCap: 60, foodCap: 600, heatCap: 0, cool: 0, sensor: 2, stealth: 0, weapons: [naval, shipAA, depth], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["power", "weapons", "control"]),
        CivUnitDef(key: "submarine", en: "Attack submarine", zh: "攻击潜艇", layer: .underwater, size: .huge, tech: ["deep_yard", "electronics"], facility: "deep_yard",
                   stages: [["steel": 50, "engine": 4], ["electronics": 10, "weapons": 4]], hours: 60, crew: 50, upkeep: 6, hp: 360, armor: 2, speed: 2.5, fuelCap: 160, fuelPerDay: 8, energyPerDay: 0,
                   ammoCap: 24, foodCap: 500, heatCap: 0, cool: 0, sensor: 1, stealth: 3, weapons: [torpedo], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["power", "weapons"]),
        CivUnitDef(key: "carrier", en: "Tidewall-class carrier", zh: "潮墙级航空母舰", layer: .sea, size: .huge, tech: ["carrier_ops"], facility: "deep_yard",
                   stages: [["steel": 200, "engine": 8], ["armor": 30, "parts": 40], ["electronics": 30, "weapons": 6]], hours: 96, crew: 400, upkeep: 20, hp: 2200, armor: 3, speed: 2.5, fuelCap: 600, fuelPerDay: 40, energyPerDay: 0,
                   ammoCap: 200, foodCap: 4000, heatCap: 0, cool: 0, sensor: 3, stealth: 0, weapons: [shipAA], hangar: 12, deckPerHour: 4, carrierBased: false, endurance: 0, parts: ["power", "hangar", "control", "weapons"]),
        CivUnitDef(key: "frame", en: "Warden heavy frame", zh: "守望者重型机兵", layer: .ground, size: .large, tech: ["frame", "frame_reactor"], facility: "frame_works",
                   stages: [["steel": 60, "armor": 20], ["parts": 30, "engine": 4], ["electronics": 20, "weapons": 4, "core": 1]], hours: 72, crew: 1, upkeep: 12, hp: 900, armor: 2, speed: 2.5, fuelCap: 0, fuelPerDay: 0, energyPerDay: 30,
                   ammoCap: 0, foodCap: 30, heatCap: 100, cool: 40, sensor: 1, stealth: 0, weapons: [beam, blade], hangar: 0, deckPerHour: 0, carrierBased: false, endurance: 0, parts: ["power", "weapons", "control", "cooling"]),
        CivUnitDef(key: "sky_carrier", en: "Highvault sky carrier", zh: "穹顶级空天母舰", layer: .highAir, size: .huge, tech: ["lift", "carrier_ops"], facility: "sky_yard",
                   stages: [["steel": 400, "armor": 60], ["parts": 120, "engine": 16], ["electronics": 120, "weapons": 10, "core": 6]], hours: 160, crew: 300, upkeep: 60, hp: 3200, armor: 3, speed: 4, fuelCap: 0, fuelPerDay: 0, energyPerDay: 240,
                   ammoCap: 0, foodCap: 3000, heatCap: 200, cool: 60, sensor: 4, stealth: 0, weapons: [skyBattery], hangar: 8, deckPerHour: 2, carrierBased: false, endurance: 0, parts: ["power", "cooling", "hangar", "control", "weapons"]),
    ]
}
