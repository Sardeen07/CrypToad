import SwiftUI

/// Top-level view: the app itself, with the lock screen layered over it when needed.
struct RootView: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(AppLock.self) private var lock
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            ContentView()

            if lock.isLocked {
                LockView()
                    .transition(.opacity)
            }
        }
        .animation(Theme.quick, value: lock.isLocked)
        .onChange(of: scenePhase) { _, phase in
            // Re-lock whenever the app leaves the foreground.
            if phase == .background && store.state.requireBiometricUnlock {
                lock.lock()
            }
        }
    }
}

struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        ZStack {
            Theme.canvas.ignoresSafeArea()

            VStack(spacing: Theme.Space.xl) {
                Text("🐸")
                    .font(.system(size: 40))
                    .frame(width: 72, height: 72)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
                    .accessibilityHidden(true)

                VStack(spacing: Theme.Space.s) {
                    Text("CrypToad is locked")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Unlock to see your balances.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometryIcon)
                }
                .buttonStyle(.primary)
                .frame(maxWidth: 280)
                .disabled(lock.isAuthenticating)

                if let error = lock.lastError {
                    Text(error)
                        .font(.footnote)
                        .foregroundStyle(Theme.negative)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding(Theme.Space.xl)
        }
        .task {
            // Prompt automatically when the lock screen appears.
            await lock.unlock()
        }
    }
}

#Preview {
    RootView()
        .environment(PortfolioStore.preview())
        .environment(AppLock())
}
