import SwiftUI
import AuthenticationServices

/// The very first screen, before onboarding. Sign in with Apple needs no
/// backend — Apple verifies identity, we just store the name it hands back.
/// It also needs the paid Developer Program membership to actually
/// authenticate in production; on a free account (or in the Simulator
/// without that capability provisioned) the request fails, and we treat
/// that exactly like tapping "Continue without signing in" rather than
/// stranding the user on this screen.
struct SignInView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            PactBackground()
            VStack(spacing: Theme.Space.lg) {
                Spacer()
                PactMark(size: 44)
                VStack(spacing: Theme.Space.sm) {
                    Text("Welcome to Prove it").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("Sign in to keep your challenges and crew tied to your account.")
                        .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, Theme.Space.xl)
                }
                Spacer()

                SignInWithAppleButton(.signIn) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handle(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 54)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
                .padding(.horizontal, Theme.Space.lg)

                Text("Needs the paid Apple Developer account to fully authenticate — until then this just continues you in.")
                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, Theme.Space.xl)

                Button("Continue without signing in") { continueAnyway() }
                    .buttonStyle(PactButtonStyle(kind: .outline))
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.xl)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let authorization):
            if let credential = authorization.credential as? ASAuthorizationAppleIDCredential {
                let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                    .compactMap { $0 }.joined(separator: " ")
                app.signedInName = name.isEmpty ? nil : name
                if let signedInName = app.signedInName { app.me.name = signedInName }
            }
            app.isSignedIn = true
        case .failure:
            continueAnyway()
        }
    }

    private func continueAnyway() {
        app.isSignedIn = true
    }
}

#Preview {
    SignInView().environment(AppModel())
}
