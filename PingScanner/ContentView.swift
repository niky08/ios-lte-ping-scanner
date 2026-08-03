import SwiftUI
import UIKit

private extension Color {
    static let oledBlack = Color(red: 0, green: 0, blue: 0)
    static let oledRow = Color(red: 0.11, green: 0.11, blue: 0.12)
}

struct ContentView: View {
  @State private var mode: ScanMode = .l3Pool

  enum ScanMode: String, CaseIterable, Identifiable {
    case l3Pool = "WL+EU TCP"
    case icmpRange = "ICMP диапазон"

    var id: String { rawValue }
  }

  var body: some View {
    ZStack {
      Color.oledBlack.ignoresSafeArea()
      NavigationStack {
        VStack(spacing: 0) {
          Picker("Режим", selection: $mode) {
            ForEach(ScanMode.allCases) { item in
              Text(item.rawValue).tag(item)
            }
          }
          .pickerStyle(.segmented)
          .padding()

          switch mode {
          case .l3Pool:
            L3PoolScanView()
          case .icmpRange:
            ICMPRangeScanView()
          }
        }
        .navigationTitle("LTE L3 Scan")
        .toolbarBackground(Color.oledBlack, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
      }
    }
    .preferredColorScheme(.dark)
    .onAppear { configureOLEDAppearance() }
  }

  private func configureOLEDAppearance() {
    UITableView.appearance().backgroundColor = .black
    UICollectionView.appearance().backgroundColor = .black
  }
}

#Preview {
  ContentView()
}
