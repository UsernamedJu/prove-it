import SwiftUI
import AuthenticationServices

/// The very first screen, before onboarding. Sign in with Apple needs no
/// backend — Apple verifies identity, we just store the name it hands back.
/// It also needs the paid Developer Program membership to actually
/// authenticate in production; on a free account (or in the Simulator
/// without that capability provisioned) the request fails, and we treat
/// that exactly like tapping "Continue without signing in" rather than
/// stranding the user on this screen.
///
/// Email/phone is the same honesty tradeoff in the other direction: there's
/// no backend to send a code to or verify against, so it's an identity
/// label, not a verified credential — framed that way in the copy rather
/// than faking a verification step that can't actually happen.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @State private var identifier = ""
    @FocusState private var identifierFocused: Bool

    var body: some View {
        ZStack {
            PactBackground()
            GeometryReader { geo in
                ScrollView {
                    VStack(spacing: Theme.Space.lg) {
                        Spacer(minLength: Theme.Space.xl)
                        PactMark(size: 44)
                        VStack(spacing: Theme.Space.sm) {
                            Text("Welcome to Prove it").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                            Text("Sign in to keep your challenges and crew tied to your account.")
                                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, Theme.Space.xl)
                        }

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

                    HStack(spacing: Theme.Space.sm) {
                        Rectangle().fill(Theme.Surface.border).frame(height: 1)
                        Text("or").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        Rectangle().fill(Theme.Surface.border).frame(height: 1)
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.top, Theme.Space.sm)

                    VStack(spacing: Theme.Space.sm) {
                        TextField("Email or phone number", text: $identifier)
                            .font(Theme.Font.body())
                            .foregroundStyle(Theme.Ink.primary)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($identifierFocused)
                            .padding(.horizontal, Theme.Space.md)
                            .frame(height: 54)
                            .glassSurface(cornerRadius: Theme.Radius.md)

                        Text("No verification code — just an identity label, since there's no server behind this yet.")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button("Continue") { continueWithIdentifier() }
                            .buttonStyle(PactButtonStyle(kind: .outline))
                            .disabled(identifier.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .padding(.horizontal, Theme.Space.lg)

                        Button("Continue without signing in") { continueAnyway() }
                            .buttonStyle(.plain)
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                            .padding(.top, Theme.Space.sm)
                        Spacer(minLength: Theme.Space.xl)
                    }
                    .frame(minHeight: geo.size.height)
                }
                .scrollDismissesKeyboard(.immediately)
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
            app.signInMethod = "Apple"
            app.isSignedIn = true
        case .failure:
            continueAnyway()
        }
    }

    private func continueWithIdentifier() {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.signedInName = trimmed
        app.signInMethod = trimmed.contains("@") ? "Email" : "Phone"
        app.isSignedIn = true
    }

    private func continueAnyway() {
        app.isSignedIn = true
    }
}

#Preview {
    SignInView().environment(AppModel())
}
