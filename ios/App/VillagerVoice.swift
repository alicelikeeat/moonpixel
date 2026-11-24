import Foundation
import MoonPixelCore
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Villagers' words written by Apple's on-device language model (iOS 26 with Apple Intelligence): free, offline,
/// nothing leaves the phone. The model is given only the villager's facts (VillagerPersona) and speaks from
/// them; without the model (an older phone, Apple Intelligence off, a language it does not speak, or a refusal)
/// the villager says their written line. A line written once for the same facts and topic is kept.
@MainActor
final class VillagerVoice {
    private var cache: [String: String] = [:]
    private var task: Task<Void, Never>?

    /// The model can be used on this phone now.
    static var available: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) { return SystemLanguageModel.default.isAvailable }
        #endif
        return false
    }

    /// Why it cannot (for the villager's card), or nil when it can.
    static func unavailableReason(zh: Bool) -> String? {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return nil
            case .unavailable(.deviceNotEligible): return zh ? "此设备不支持端侧 AI" : "this device has no on-device AI"
            case .unavailable(.appleIntelligenceNotEnabled): return zh ? "Apple 智能未开启" : "Apple Intelligence is off"
            case .unavailable(.modelNotReady): return zh ? "端侧模型还在下载" : "the on-device model is still downloading"
            @unknown default: return zh ? "端侧 AI 暂不可用" : "on-device AI is unavailable"
            }
        }
        #endif
        return zh ? "需要 iOS 26 和 Apple 智能" : "needs iOS 26 and Apple Intelligence"
    }

    /// Loads the model ahead of the first words (when a villager is chosen).
    func prewarm() {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *), Self.available { LanguageModelSession().prewarm() }
        #endif
    }

    func cancel() { task?.cancel(); task = nil }

    /// Words for a villager on a topic: `done` gets them, or nil (say the written line).
    func say(_ p: VillagerPersona, topic: String, done: @escaping (String?) -> Void) {
        cancel()
        let key = p.key(topic: topic)
        if let c = cache[key] { done(c); return }
        guard Self.available else { done(nil); return }
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            let instructions = p.instructions, prompt = p.prompt(topic: topic)
            task = Task { [weak self] in
                do {
                    let session = LanguageModelSession(instructions: instructions)
                    let r = try await session.respond(to: prompt)
                    guard !Task.isCancelled else { return }
                    let line = VillagerVoice.tidy(r.content)
                    if !line.isEmpty { self?.cache[key] = line }
                    done(line.isEmpty ? nil : line)
                } catch {
                    if !Task.isCancelled { done(nil) }
                }
            }
            return
        }
        #endif
        done(nil)
    }

    /// One short paragraph without quotation marks round it.
    static func tidy(_ s: String) -> String {
        var t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        for q in ["「", "」", "“", "”", "\"", "『", "』"] { t = t.replacingOccurrences(of: q, with: "") }
        t = t.replacingOccurrences(of: "\n", with: " ")
        return String(t.prefix(160))
    }
}
