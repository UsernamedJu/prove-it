import SwiftUI

/// A group shown as an orbit: you in the center, everyone else arranged
/// around you in a circle. Tapping a member opens their own metrics.
struct GroupDetailView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let groupID: UUID

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var group: ContactGroup? { app.groups.first { $0.id == groupID } }

    var body: some View {
        if let group {
            content(group)
        } else {
            Text("This group is gone.").foregroundStyle(Theme.Ink.secondary)
        }
    }

    private func content(_ group: ContactGroup) -> some View {
        let members = app.members(in: group)
        return ScrollView {
            VStack(spacing: Theme.Space.xl) {
                header(group, count: members.count)
                orbit(members)
                membersList(members)
            }
            .padding(Theme.Space.lg)
            .padding(.bottom, Theme.Space.xxl)
        }
        .background(PactBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task { await app.refreshCrewProfiles() }
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
                NavigationLink(value: Route.groupChat(group.id)) {
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

    private func header(_ group: ContactGroup, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(group.name).font(Theme.Font.h1()).foregroundStyle(Theme.Ink.primary)
            Text("\(count) people orbiting you").font(Theme.Font.body()).foregroundStyle(Theme.Ink.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Space.md)
    }

    // MARK: Orbit — you at the center, members ringed around at even angles
    //
    // Driven by TimelineView from wall-clock time rather than a @State var
    // animated via withAnimation(...repeatForever()) — the same pattern
    // PactMark's logo and PactBackground's color wash already use. A
    // 60-second repeatForever kept SwiftUI's animation system actively
    // interpolating this whole view's transforms indefinitely for as long
    // as the screen was on screen, which is what made it read as laggy
    // once it was running alongside everything else (the background wash,
    // a kept-alive tab). Computing the angle directly from the current
    // frame's timestamp is cheaper and, as a real bonus, finally respects
    // Reduce Motion — the old version spun regardless.

    private func orbit(_ members: [Member]) -> some View {
        let radius: CGFloat = 118
        return TimelineView(.animation(paused: reduceMotion)) { context in
            let seconds = context.date.timeIntervalSinceReferenceDate
            let orbitRotation = (seconds.truncatingRemainder(dividingBy: 60) / 60) * 360
            ZStack {
                ZStack {
                    ForEach([0.55, 0.78, 1.0], id: \.self) { scale in
                        Circle()
                            .stroke(Theme.Surface.border, lineWidth: 1)
                            .frame(width: radius * 2 * scale, height: radius * 2 * scale)
                    }
                }
                .rotationEffect(.degrees(orbitRotation * 0.4))

                ZStack {
                    ForEach(Array(members.enumerated()), id: \.element.id) { i, member in
                        let angle = (2 * Double.pi / Double(max(members.count, 1))) * Double(i) - .pi / 2
                        let x = cos(angle) * radius
                        let y = sin(angle) * radius
                        NavigationLink(value: Route.member(member.id)) {
                            VStack(spacing: 4) {
                                InitialBadge(name: member.name, size: 54, photoData: member.photoData)
                                    .overlay(Circle().stroke(swatchColor(for: member.name), lineWidth: 2))
                                Text(member.name.split(separator: " ").first.map(String.init) ?? member.name)
                                    .font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.secondary)
                            }
                            .rotationEffect(.degrees(-orbitRotation))
                        }
                        .buttonStyle(.plain)
                        .offset(x: x, y: y)
                    }
                }
                .rotationEffect(.degrees(orbitRotation))

                VStack(spacing: 4) {
                    InitialBadge(name: app.me.name, size: 74, overrideColor: app.meColor, photoData: app.myProfilePhotoData)
                        .overlay(Circle().stroke(Theme.Ink.primary, lineWidth: 3).padding(-5))
                        .shadow(color: app.meColor.opacity(0.45), radius: 16)
                        .scaleEffect(reduceMotion ? 1.0 : pulseScale(seconds))
                    Text(app.me.name).font(Theme.Font.eyebrow()).foregroundStyle(Theme.Ink.primary)
                }
            }
        }
        .frame(width: radius * 2 + 60, height: radius * 2 + 60)
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Space.md)
    }

    /// A sine wave standing in for easeInOut's shape, evaluated directly
    /// from the clock instead of needing withAnimation's own repeatForever
    /// interpolation to reproduce the same gentle breathing feel.
    private func pulseScale(_ seconds: Double) -> CGFloat {
        let cycle = 2.6
        let t = (seconds.truncatingRemainder(dividingBy: cycle)) / cycle
        let eased = (sin(t * 2 * .pi - .pi / 2) + 1) / 2
        return 1.0 + eased * 0.06
    }

    private func membersList(_ members: [Member]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            SectionHeader(title: "Members")
            ForEach(members) { member in
                NavigationLink(value: Route.member(member.id)) {
                    HStack(spacing: Theme.Space.sm) {
                        InitialBadge(name: member.name, size: 40, photoData: member.photoData)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.name).font(Theme.Font.h3()).foregroundStyle(Theme.Ink.primary)
                            Text(member.ageBand.rawValue).font(Theme.Font.caption()).foregroundStyle(Theme.Ink.tertiary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(Theme.Ink.tertiary)
                    }
                    .padding(Theme.Space.sm)
                    .glassSurface(cornerRadius: Theme.Radius.sm)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

#Preview {
    NavigationStack { GroupDetailView(groupID: Fixtures.groups[0].id) }.environment(AppModel())
}
