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
        .animation(.easeInOut(duration: 0.2), value: lock.isLocked)
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
            Theme.background.ignoresSafeArea()

            VStack(spacing: 20) {
                Text("🐸")
                    .font(.system(size: 64))
                Text("CrypToad is locked")
                    .font(.title2.bold())
                    .foregroundStyle(.white)

                Button {
                    Task { await lock.unlock() }
                } label: {
                    Label("Unlock with \(lock.biometryName)", systemImage: lock.biometryIcon)
                        .fontWeight(.semibold)
                        .frame(maxWidth: 260)
                        .padding()
                        .background(Color.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .disabled(lock.isAuthenticating)

                if let error = lock.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
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
