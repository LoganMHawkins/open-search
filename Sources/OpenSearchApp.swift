import SwiftUI

@main
struct OpenSearchApp: App {
    @StateObject private var model = AppModel()

    init() {
        Brand.registerFonts()
        if let i = CommandLine.arguments.firstIndex(of: "--export-icon"), CommandLine.arguments.indices.contains(i + 1) {
            let dir = CommandLine.arguments[i + 1]
            DispatchQueue.main.async { IconExporter.run(into: dir) }
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(Brand.orange)
                .frame(minWidth: 1120, minHeight: 720)
                #if DEBUG
                .preferredColorScheme(CommandLine.arguments.contains("--light") ? .light : nil)
                #endif
        }
        .defaultSize(width: 1380, height: 880)
        .windowToolbarStyle(.unified(showsTitle: true))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Tools") {
                ForEach(Array(Tool.allCases.enumerated()), id: \.element) { i, tool in
                    if i < 9 {
                        Button(tool.title) { model.select(tool) }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                    } else {
                        Button(tool.title) { model.select(tool) }
                    }
                }
            }
            CommandGroup(after: .appSettings) {
                Button("API Key & Credits…") { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
    }
}
