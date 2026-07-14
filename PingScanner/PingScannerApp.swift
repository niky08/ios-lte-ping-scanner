import SwiftUI

@main
struct PingScannerApp: App {
    init() {
        UITableView.appearance().backgroundColor = .black
        UICollectionView.appearance().backgroundColor = .black
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .background(Color.black)
        }
    }
}