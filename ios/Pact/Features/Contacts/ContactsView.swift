import SwiftUI

struct ContactsView: View {
    @Environment(AppModel.self) private var app
    @State private var newName = ""
    @State private var showNewGroup = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Crew").font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
                    Text("Family, friends, anyone you challenge.")
                        .font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
                }
                .padding(.top, Theme.Space.md)

                HStack(spacing: Theme.Space.sm) {
                    TextField("Add a name", text: $newName)
                        .font(Theme.Font.body())
                        .foregroundStyle(Theme.Ink.primary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 50)
                        .glassSurface(cornerRadius: Theme.Radius.md)
                    Button {
                        app.addContact(name: newName)
                        newName = ""
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundStyle(.white)
                            .frame(width: 50, height: 50)
                            .background(Theme.Brand.purple)
                            .clipShape(Circle())
                    }
                }

                groupsSection

                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeader(title: "Everyone")
                    ForEach(app.crew) { member in
                        ContactRow(member: member, sharedChallenges: sharedChallengeCount(with: member))
                    }
                }
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .sheet(isPresented: $showNewGroup) { NewGroupSheet() }
        .navigationDestination(for: Route.self) { route in
            switch route {
            case .challenge(let id): ChallengeDetailView(challengeID: id)
            case .createChallenge(let seed): CreateChallengeView(seed: seed)
            case .moodSurvey: MoodSurveyView()
            case .group(let id): GroupDetailView(groupID: id)
            case .member(let id): MemberDetailView(memberID: id)
            }
        }
    }

    private var groupsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Groups")
            ForEach(app.groups) { group in
                NavigationLink(value: Route.group(group.id)) {
                    PactCard(tint: Theme.Brand.cyan) {
                        HStack(spacing: Theme.Space.sm) {
                            ZStack {
                                Circle().fill(Theme.Brand.cyan.opacity(0.2)).frame(width: 40, height: 40)
                                Image(systemName: "person.3.fill").foregroundStyle(Theme.Brand.cyan)
                            }
                            VStack(alignment: .leading, spacing: 2) {
                                Text(group.name).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                                Text(app.members(in: group).map(\.name).joined(separator: ", "))
                                    .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.Ink.tertiary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            Button {
                showNewGroup = true
            } label: {
                HStack(spacing: 6) { Image(systemName: "person.badge.plus"); Text("New Group") }
            }
            .buttonStyle(PactButtonStyle(kind: .outline, height: 46))
        }
    }

    private func sharedChallengeCount(with member: Member) -> Int {
        app.challenges.filter { c in c.standings.contains { $0.member.id == member.id } }.count
    }
}

private struct ContactRow: View {
    @Environment(AppModel.self) private var app
    let member: Member
    let sharedChallenges: Int

    var body: some View {
        let fit = app.fitTag(for: member)
        NavigationLink(value: Route.member(member.id)) {
            PactCard(tint: swatchColor(for: member.name)) {
                HStack(spacing: Theme.Space.sm) {
                    InitialBadge(name: member.name, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.name).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                        Text("\(member.ageBand.rawValue) · \(sharedChallenges) shared challenge\(sharedChallenges == 1 ? "" : "s")")
                            .font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        Image(systemName: fit.kind.icon).foregroundStyle(Theme.Brand.cyan)
                        Text(fit.label.replacingOccurrences(of: "Best fit: ", with: ""))
                            .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.tertiary)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 70)
                    }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct NewGroupSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var selected: Set<UUID> = []

    var body: some View {
        NavigationStack {
            ZStack {
                PactBackground()
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    TextField("Group name (e.g. Family)", text: $name)
                        .font(Theme.Font.h2())
                        .foregroundStyle(Theme.Ink.primary)
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 56)
                        .glassSurface(cornerRadius: Theme.Radius.md)

                    VStack(spacing: Theme.Space.xs) {
                        ForEach(app.crew) { member in
                            let on = selected.contains(member.id)
                            Button {
                                if on { selected.remove(member.id) } else { selected.insert(member.id) }
                            } label: {
                                HStack(spacing: Theme.Space.sm) {
                                    InitialBadge(name: member.name, size: 36)
                                    Text(member.name).font(Theme.Font.body()).foregroundStyle(Theme.Ink.primary)
                                    Spacer()
                                    Image(systemName: on ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(on ? Theme.Brand.purple : Theme.Ink.tertiary)
                                }
                                .padding(Theme.Space.sm)
                                .glassSurface(cornerRadius: Theme.Radius.sm, tint: on ? Theme.Brand.purple : nil)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    Button("Create Group") {
                        app.createGroup(name: name, memberIDs: Array(selected))
                        dismiss()
                    }
                    .buttonStyle(PactButtonStyle(kind: .primary))
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || selected.isEmpty)
                }
                .padding(Theme.Space.lg)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.Ink.secondary)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    NavigationStack { ContactsView() }.environment(AppModel())
}
