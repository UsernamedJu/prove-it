import SwiftUI
import AuthenticationServices
import UIKit

/// The very first screen, before onboarding. A full-bleed photo behind
/// everything (Strava's own sign-in follows this exact recipe: hero image,
/// wordmark near the top, compact sign-in controls sitting a little above
/// the very bottom, not vertically centered and not scrollable) — this
/// screen doesn't scroll, so it has to actually fit on one page, which is
/// why the controls are compact instead of full-size buttons.
///
/// Every row below is sized with an explicit, computed width from
/// `GeometryReader` rather than a flexible `.frame(maxWidth: .infinity)`.
/// That's not stylistic — a flexible frame here was observed to render
/// full-bleed (ignoring the horizontal padding entirely) whenever this
/// screen's photo/gradient background was present, and correctly inset
/// with a plain color background, with zero other code changes. Same
/// modifiers, same view, two different outcomes depending on an unrelated
/// sibling — that's this SDK's layout engine, not something to out-clever
/// with more flexible frames. An explicit number sidesteps it entirely.
///
/// Sign in with Apple needs no backend — Apple verifies identity, we just
/// store the name it hands back. It also needs the paid Developer Program
/// membership to actually authenticate in production; on a free account (or
/// in the Simulator without that capability provisioned) the request fails,
/// and we treat that exactly like tapping "Continue without signing in"
/// rather than stranding the user on this screen.
///
/// Email/phone is the same honesty tradeoff in the other direction: there's
/// no backend to send a code to or verify against, so it's an identity
/// label, not a verified credential. There's no separate "Continue" button
/// for it — the keyboard's own Go key submits, same as a search field.
struct SignInView: View {
    @Environment(AppModel.self) private var app
    @State private var identifier = ""
    @FocusState private var identifierFocused: Bool
    /// Kept alive for the duration of one request — `ASAuthorizationController`
    /// doesn't retain its own delegate.
    @State private var appleCoordinator: AppleSignInCoordinator?

    var body: some View {
        ZStack {
            // Background layer — full-bleed, deliberately ignores the safe
            // area so the photo runs edge-to-edge under the notch.
            GeometryReader { geo in
                Image("photo-login")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.32), location: 0),
                        .init(color: .black.opacity(0.12), location: 0.35),
                        .init(color: .black.opacity(0.2), location: 0.6),
                        .init(color: .black.opacity(0.75), location: 1),
                    ],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .ignoresSafeArea()

            // Content layer — a *separate* `GeometryReader` that does NOT
            // ignore the safe area, so `geo.size` here already excludes the
            // notch/Dynamic Island and the home indicator. Regular design-
            // system spacing on top of that is what actually places things
            // correctly on every device, rather than a guessed pixel
            // constant tuned to look right on just one.
            GeometryReader { geo in
                VStack(spacing: 0) {
                    logoBlock
                        .padding(.top, Theme.Space.xxl)
                    Spacer(minLength: 0)
                    controls(width: geo.size.width - Theme.Space.lg * 2)
                        .padding(.bottom, Theme.Space.lg)
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
        }
    }

    private var logoBlock: some View {
        VStack(spacing: Theme.Space.xs) {
            PactMark(size: 34)
            Text("Prove it")
                .font(Theme.Font.wordmark(24))
                .tracking(-0.2)
                .foregroundStyle(.white)
            Text("Friendly challenges. Real accountability.")
                .font(Theme.Font.caption())
                .foregroundStyle(.white.opacity(0.85))
        }
        .shadow(color: .black.opacity(0.35), radius: 8, y: 2)
    }

    /// Sits a bit above the very bottom edge (not flush against the home
    /// indicator, not centered on screen) and every control here is
    /// deliberately compact — a full-size 54pt button stack didn't leave
    /// enough breathing room around the photo underneath it. `width` is the
    /// exact, already-inset row width every child below renders at.
    private func controls(width: CGFloat) -> some View {
        VStack(spacing: Theme.Space.sm) {
            appleButton(width: width)

            HStack(spacing: Theme.Space.sm) {
                Rectangle().fill(.white.opacity(0.3)).frame(height: 1)
                Text("or").font(Theme.Font.caption()).foregroundStyle(.white.opacity(0.75))
                Rectangle().fill(.white.opacity(0.3)).frame(height: 1)
            }
            .frame(width: width)

            TextField("", text: $identifier, prompt: Text("Email or phone number").foregroundStyle(.white.opacity(0.55)))
                .font(Theme.Font.body())
                .foregroundStyle(.white)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($identifierFocused)
                .submitLabel(.go)
                .onSubmit { continueWithIdentifier() }
                .padding(.horizontal, Theme.Space.md)
                .frame(width: width, height: 42)
                .photoOverlaySurface(cornerRadius: Theme.Radius.md)

            Button("Continue without signing in") { continueAnyway() }
                .buttonStyle(.plain)
                .font(Theme.Font.caption()).foregroundStyle(.white.opacity(0.8))
                .padding(.top, Theme.Space.xxs)
                .frame(width: width)
        }
        .frame(width: width)
    }

    /// `SignInWithAppleButton` is skipped on purpose — its native background
    /// layer ignores every SwiftUI `.frame`/`.clipShape` constraint in this
    /// SDK, so it can never actually be made to fit. This is a plain
    /// SwiftUI button styled to match, driving the real
    /// `ASAuthorizationController` API underneath — same outcome, reliable
    /// size.
    /// Built with the exact same shape as the email field below it —
    /// explicit `.frame(width:height:)` on the outer control, then
    /// background, then clipShape — so the two rows are guaranteed to
    /// match. The earlier version put a *flexible* `.frame(maxWidth:
    /// .infinity)` inside the label before the exact frame outside it, and
    /// that mismatch was rendering visibly bigger than the text field.
    private func appleButton(width: CGFloat) -> some View {
        Button {
            let coordinator = AppleSignInCoordinator(onCompletion: handle)
            appleCoordinator = coordinator
            coordinator.start()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .medium))
                Text("Sign in with Apple").font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.black)
        }
        .buttonStyle(.plain)
        .frame(width: width, height: 42)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
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
        appleCoordinator = nil
    }

    private func continueWithIdentifier() {
        let trimmed = identifier.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        app.signedInName = trimmed
        app.signInMethod = trimmed.contains("@") ? "Email" : "Phone"
        app.isSignedIn = true
    }

    private func continueAnyway() {
        app.isGuestSession = true
    }
}

/// Drives the real Sign in with Apple request/response cycle —
/// `ASAuthorizationController` needs a delegate + presentation anchor, which
/// only make sense as a small UIKit-facing coordinator, not a SwiftUI view.
final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    private let onCompletion: (Result<ASAuthorization, Error>) -> Void

    init(onCompletion: @escaping (Result<ASAuthorization, Error>) -> Void) {
        self.onCompletion = onCompletion
    }

    func start() {
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName]
        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
        onCompletion(.success(authorization))
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        onCompletion(.failure(error))
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

#Preview {
    SignInView().environment(AppModel())
}
