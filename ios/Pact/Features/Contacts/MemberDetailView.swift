import SwiftUI

/// Another crew member's own metrics and data — their fit tag, their Fair
/// Play target, and their standing inside every challenge you share.
struct MemberDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let memberID: UUID

    private var member: Member? { app.crew.first { $0.id == memberID } }

    var body: some View {
        if let member {
            content(member)
        } else {
            Text("This person is gone.").foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func content(_ member: Member) -> some View {
        let fit = app.fitTag(for: member)
        let shared = app.challenges.filter { c in c.standings.contains { $0.member.id == member.id } }

        return ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                HStack(spacing: Theme.Space.md) {
                    InitialBadge(name: member.name, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                        Text(member.ageBand.rawValue).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                    }
                    Spacer()
                }
                .padding(.top, Theme.Space.md)

                PactCard(tint: Theme.Brand.cyan) {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        HStack(spacing: 6) {
                            Image(systemName: fit.kind.icon).foregroundStyle(Theme.Brand.cyan)
                            Text("Best Fit").font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        }
                        Text(fit.label).font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                        Divider().overlay(Theme.Surface.border)
                        HStack {
                            Text("Fair Play target").font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                            Spacer()
                            Text("\(member.ageBand.fairPlayStepTarget.formatted()) steps/day")
                                .font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeader(title: "Shared Challenges")
                    if shared.isEmpty {
                        Text("No challenges together yet.")
                            .font(Theme.Font.body()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    ForEach(shared) { challenge in
                        if let standing = challenge.standings.first(where: { $0.member.id == member.id }) {
                            let hide = challenge.blindReveal && challenge.status == .active
                            NavigationLink(value: Route.challenge(challenge.id)) {
                                PactCard(tint: challenge.tint) {
                                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                                        HStack {
                                            Text(challenge.title).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                                            Spacer()
                                            Text("#\(standing.rank)").font(Theme.Font.number(18)).foregroundStyle(challenge.tint)
                                        }
                                        ProgressPill(progress: standing.progress, tint: challenge.tint, blurred: hide)
                                        Text("\(Int(standing.progress * 100))% · \(standing.trendDelta) this week")
                                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                            .blur(radius: hide ? 4 : 0)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 40, height: 40)
                        .glassSurface(cornerRadius: 20)
                        .clipShape(Circle())
                }
                Spacer()
                NavigationLink(value: Route.directChat(member.id)) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(Theme.Ink.secondary)
                        .frame(width: 40, height: 40)
                        .glassSurface(cornerRadius: 20)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, Theme.Space.md)
            .padding(.top, Theme.Space.xs)
        }
    }
}

#Preview {
    NavigationStack { MemberDetailView(memberID: Fixtures.mom.id) }.environment(AppModel())
}
