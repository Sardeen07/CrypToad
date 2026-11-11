import AuthenticationServices
import CryptoKit
import SwiftUI
import CrypToadCore

/// Settings → Account: sign in (Apple or demo), server address, sign out, delete account.
struct AccountSection: View {
    @Environment(PortfolioStore.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    /// A reference type so the nonce set in the request closure is the one read on completion.
    @State private var nonce = NonceHolder()
    @State private var confirmDelete = false

    var body: some View {
        if let account = store.account {
            signedIn(account)
        } else {
            signedOut
        }
    }

    // MARK: Signed out

    @ViewBuilder
    private var signedOut: some View {
        @Bindable var store = store
        Section {
            SignInWithAppleButton(.signIn) { request in
                nonce.current = AppleNonce()
                request.requestedScopes = [.fullName, .email]
                request.nonce = nonce.current.hashed
            } onCompletion: { result in
                handleApple(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 44)
            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

            Button {
                Task { await store.startDemoAccount() }
            } label: {
                Label("Try a demo account", systemImage: "person.crop.circle.badge.plus")
            }
            .disabled(store.isWorking || store.serverInfo?.demoAccounts == false)

            TextField("Server", text: $store.serverURLString)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .font(.footnote.monospaced())
                .onSubmit { Task { await store.loadServerInfo() } }

            if store.isWorking {
                ProgressView("Signing in…")
            }
        } header: {
            Text("Account")
        } footer: {
            Text(serverFooter)
        }
        .task(id: store.serverURLString) {
            try? await Task.sleep(for: .milliseconds(400))
            await store.loadServerInfo()
        }
    }

    private var serverFooter: String {
        let base = "Sign in to keep your portfolio on the CrypToad server, so round-ups, trades, and DCA buys run on a real double-entry ledger. Signed out, everything runs on this device."
        guard let info = store.serverInfo else { return base + "\n\nServer not reachable. Start it with `docker compose up` in backend/, or enter your deployed URL." }
        return base + "\n\nConnected to server v\(info.version)."
    }

    private func handleApple(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            guard
                let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                let tokenData = credential.identityToken,
                let token = String(data: tokenData, encoding: .utf8)
            else {
                store.alertMessage = "Apple didn't return an identity token. Please try again."
                return
            }
            let name = credential.fullName.map { PersonNameComponentsFormatter.localizedString(from: $0, style: .default) }
            let raw = nonce.current.raw
            Task { await store.signInWithApple(identityToken: token, rawNonce: raw, fullName: name) }
        case .failure(let error):
            if (error as? ASAuthorizationError)?.code == .canceled { return }
            store.alertMessage = "Sign in with Apple isn't available in this build (\(error.localizedDescription)). "
                + "It needs an Apple Developer team; use a demo account for now."
        }
    }

    // MARK: Signed in

    @ViewBuilder
    private func signedIn(_ account: AccountUser) -> some View {
        Section {
            LabeledContent("Signed in as", value: account.label)
            LabeledContent("Method", value: account.signInMethod == "apple" ? "Sign in with Apple" : "Demo account")
            LabeledContent("Server", value: store.serverURLString)
                .font(.footnote)
            LabeledContent("Last synced") {
                if store.isSyncing {
                    ProgressView()
                } else if let date = store.lastSyncedAt {
                    Text(date, style: .relative) + Text(" ago")
                } else {
                    Text("—")
                }
            }
            Button("Sync now") { Task { await store.refreshAll() } }
                .disabled(store.isSyncing)
            Button("Sign out") { Task { await store.signOut() } }
            Button("Delete account", role: .destructive) { confirmDelete = true }
        } header: {
            Text("Account")
        } footer: {
            Text("Balances and history live on the server. DCA schedules and Face ID stay on this device.")
        }
        .confirmationDialog("Delete your CrypToad account?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await store.deleteAccount() } }
        } message: {
            Text("This signs you out everywhere and removes your personal data and bank link. It can't be undone.")
        }

        BankSection()
    }
}

/// Settings → Bank: link a bank through Plaid so its purchases are rounded up.
struct BankSection: View {
    @Environment(PortfolioStore.self) private var store
    @State private var confirmUnlink = false

    var body: some View {
        Section {
            if !store.bank.available {
                Text("Bank linking isn't set up on this server yet.")
                    .foregroundStyle(.secondary)
            } else if store.bank.linked {
                LabeledContent("Bank", value: store.bank.institutionName ?? "Linked")
                if let synced = store.bank.lastSyncedAt {
                    LabeledContent("Last checked") { Text(synced, style: .relative) + Text(" ago") }
                }
                Button {
                    Task { await store.syncBank() }
                } label: {
                    Label("Round up new purchases", systemImage: "arrow.triangle.2.circlepath")
                }
                .disabled(store.isWorking)
                Button("Unlink bank", role: .destructive) { confirmUnlink = true }
            } else {
                Button {
                    Task { await store.linkSandboxBank() }
                } label: {
                    Label(store.bank.sandbox ? "Link test bank (Plaid Sandbox)" : "Link bank account", systemImage: "building.columns")
                }
                .disabled(store.isWorking || !store.bank.sandbox)
            }
            if store.isWorking {
                ProgressView()
            }
        } header: {
            Text("Bank")
        } footer: {
            Text("Purchases from your linked bank are rounded up and the spare change is invested from your USDC, split by your round-up allocation. Bank access is through Plaid; CrypToad never sees your bank login.")
        }
        .confirmationDialog("Unlink your bank?", isPresented: $confirmUnlink, titleVisibility: .visible) {
            Button("Unlink", role: .destructive) { Task { await store.unlinkBank() } }
        }
    }
}

final class NonceHolder {
    var current = AppleNonce()
}

/// A one-time random nonce for Sign in with Apple. Apple embeds its SHA-256 in the identity
/// token; the server checks it against the raw value, so a stolen token can't be replayed.
struct AppleNonce {
    let raw: String

    init() {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        raw = Data(bytes).base64EncodedString()
    }

    var hashed: String {
        SHA256.hash(data: Data(raw.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
