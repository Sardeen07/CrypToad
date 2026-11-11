import SwiftUI
import CrypToadCore

enum Tab: Hashable {
    case home, invest, roundUps, card
}

enum ActiveSheet: String, Identifiable {
    case settings, trade, roundUpAllocation, dcaAllocation, dcaSchedule
    var id: String { rawValue }
}

/// App shell: native tab bar, a navigation stack per tab, and the app's sheets and alerts.
struct ContentView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppLock.self) private var lock

    @State private var tab: Tab = .home
    @State private var sheet: ActiveSheet?

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                HomeView(present: present)
                    .navigationTitle("Portfolio")
                    .settingsToolbar { present(.settings) }
            }
            .tabItem { Label("Home", systemImage: "house") }
            .tag(Tab.home)

            NavigationStack {
                DCAView(present: present)
                    .navigationTitle("Invest")
                    .adaptiveTitleDisplayMode()
                    .settingsToolbar { present(.settings) }
            }
            .tabItem { Label("Invest", systemImage: "chart.line.uptrend.xyaxis") }
            .tag(Tab.invest)

            NavigationStack {
                RoundUpView(present: present)
                    .navigationTitle("Round-Ups")
                    .adaptiveTitleDisplayMode()
                    .settingsToolbar { present(.settings) }
            }
            .tabItem { Label("Round-Ups", systemImage: "arrow.up.circle") }
            .tag(Tab.roundUps)

            NavigationStack {
                CardView()
                    .navigationTitle("Card")
                    .adaptiveTitleDisplayMode()
                    .settingsToolbar { present(.settings) }
            }
            .tabItem { Label("Card", systemImage: "creditcard") }
            .tag(Tab.card)
        }
        .task {
            await store.keepPricesFresh()
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(store)
                .environment(lock)
                .tint(Theme.brand)
        }
        .alert("CrypToad", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private func sheetContent(_ sheet: ActiveSheet) -> some View {
        switch sheet {
        case .settings:
            SettingsSheet()
        case .trade:
            TradeSheet()
        case .roundUpAllocation:
            AllocationEditorSheet(title: "Round-Up Allocation", initial: store.state.roundUps.allocation) {
                store.setRoundUpAllocation($0)
            }
        case .dcaAllocation:
            AllocationEditorSheet(title: "DCA Allocation", initial: store.state.dca.allocation) {
                store.setDCAAllocation($0)
            }
        case .dcaSchedule:
            DCAScheduleSheet()
        }
    }

    private func present(_ sheet: ActiveSheet) {
        self.sheet = sheet
    }

    private var alertIsPresented: Binding<Bool> {
        Binding(
            get: { store.alertMessage != nil },
            set: { if !$0 { store.alertMessage = nil } }
        )
    }
}

#Preview {
    ContentView()
        .environment(PortfolioStore.preview())
        .environment(AppLock())
        .tint(Theme.brand)
}
