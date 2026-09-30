import SwiftUI
import CrypToadCore

enum Screen: Hashable {
    case home, invest, card, roundUp, history
}

enum ActiveSheet: String, Identifiable {
    case settings, trade, roundUpAllocation, dcaAllocation, dcaSchedule
    var id: String { rawValue }
}

/// App shell: header, the current screen, bottom navigation, and sheets.
struct ContentView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppLock.self) private var lock

    @State private var screen: Screen = .home
    @State private var sheet: ActiveSheet?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HeaderView(onSettings: { sheet = .settings })

                ScrollView {
                    VStack(spacing: 16) {
                        currentScreen
                    }
                    .padding(16)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    await store.refreshPrices()
                }

                BottomNavView(current: $screen)
            }
        }
        .task {
            await store.keepPricesFresh()
        }
        .sheet(item: $sheet) { sheet in
            sheetContent(sheet)
                .environment(store)
                .environment(lock)
                .preferredColorScheme(.dark)
        }
        .alert("CrypToad", isPresented: alertIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var currentScreen: some View {
        switch screen {
        case .home:
            HomeView(navigate: navigate, present: present)
        case .invest:
            DCAView(navigate: navigate, present: present)
        case .card:
            CardView()
        case .roundUp:
            RoundUpView(navigate: navigate, present: present)
        case .history:
            TransactionHistoryView(navigate: navigate)
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

    private func navigate(to screen: Screen) {
        withAnimation(.easeInOut(duration: 0.15)) { self.screen = screen }
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
}
