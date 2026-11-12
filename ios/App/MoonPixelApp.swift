import SwiftUI
import SpriteKit
import MoonPixelCore

@main
struct MoonPixelApp: App {
    @StateObject private var model = GameModel()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: phase) { _, p in
            if p != .active { model.save(announce: false) }      // iOS may kill a backgrounded app at any time
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: GameModel

    var body: some View {
        ZStack {
            if let scene = model.scene {
                SpriteView(scene: scene, preferredFramesPerSecond: 60).ignoresSafeArea()
                HUDView()
            } else {
                MenuView()
            }
        }
        .onAppear { model.handleLaunchArguments() }
    }
}

/// Real system Liquid Glass on iOS 26+, a material fallback before that.
extension View {
    @ViewBuilder func glass<S: Shape>(_ shape: S) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self.background(.ultraThinMaterial, in: shape)
        }
        #else
        self.background(.ultraThinMaterial, in: shape)
        #endif
    }
}

func L(_ zh: String, _ en: String) -> String { GameModel.zh ? zh : en }
