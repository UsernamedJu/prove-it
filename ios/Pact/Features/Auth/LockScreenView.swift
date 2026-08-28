import SwiftUI

/// Shown whenever the app returns to the foreground with App Lock on.
/// Unlike Sign in with Apple, Face ID / Touch ID works fully today on any
/// account tier — no capability or paid membership needed.
struct LockScreenView: View {
    @Environment(AppModel.self) private var app
    @State private var attempting = false
    @State private var failed = false

    var body: some View {
        ZStack {
            Theme.Surface.bg.ignoresSafeArea()
            VStack(spacing: Theme.Space.lg) {
                Spacer()
                PactMark(size: 40)
                Image(systemName: "faceid").font(.system(size: 44)).foregroundStyle(Theme.Brand.purple)
                Text("Prove it is locked").font(Theme.Font.h2()).foregroundStyle(Theme.Ink.primary)
                if failed {
                    Text("Couldn't verify — try again.").font(Theme.Font.caption()).foregroundStyle(Theme.Brand.coral)
                }
                Spacer()
                Button {
                    unlock()
                } label: {
                    HStack(spacing: 6) { Image(systemName: "faceid"); Text("Unlock") }
                }
                .buttonStyle(PactButtonStyle(kind: .primary))
                .padding(.horizontal, Theme.Space.lg)
                .padding(.bottom, Theme.Space.xl)
                .disabled(attempting)
            }
        }
        .onAppear { unlock() }
    }

    private func unlock() {
        attempting = true
        failed = false
        Task {
            let ok = await BiometricLock.unlock(reason: "Unlock Prove it")
            attempting = false
            if ok { app.isUnlocked = true } else { failed = true }
        }
    }
}

#Preview {
    LockScreenView().environment(AppModel())
}
