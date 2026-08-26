import SwiftUI
import ThreadmarkCore

struct MenuPanel: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Divider()

            if model.connection == nil {
                PairingView(model: model)
            } else if model.showsSettings {
                SettingsView(model: model)
            } else {
                ActivityList(model: model)
            }

            if let error = model.errorMessage {
                ErrorBanner(message: error)
            }

            Divider()
            Footer(model: model)
        }
        .frame(width: 380)
        .background(.ultraThinMaterial)
    }
}

private struct Header: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.accentColor.gradient)
                Image(systemName: "bolt.horizontal.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text("Threadmark")
                    .font(.headline)
                Text(model.connection?.label ?? "Mac activity monitor")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()
            ConnectionPill(state: model.connectionState)
        }
        .padding(14)
    }
}

private struct ConnectionPill: View {
    let state: AppModel.ConnectionState

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(.quaternary, in: Capsule())
        .help(help)
    }

    private var label: String {
        switch state {
        case .disconnected: "Not paired"
        case .connecting: "Pairing"
        case .online: "Live"
        case .offline: "Offline"
        }
    }

    private var color: Color {
        switch state {
        case .disconnected: .secondary
        case .connecting: .orange
        case .online: .green
        case .offline: .red
        }
    }

    private var help: String {
        if case let .offline(message) = state { return message }
        return label
    }
}

private struct PairingView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Pair this Mac")
                    .font(.title3.weight(.semibold))
                Text("Create a pairing link in T3 Code, then paste it here. The one-time token is exchanged and only the resulting credential is kept in Keychain.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SecureField("Paste pairing URL", text: $model.pairingURL)
                .textFieldStyle(.roundedBorder)
                .onSubmit { Task { await model.connect() } }

            Button {
                Task { await model.connect() }
            } label: {
                HStack {
                    if model.connectionState == .connecting {
                        ProgressView().controlSize(.small)
                    }
                    Text(model.connectionState == .connecting ? "Pairing…" : "Connect to T3")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.connectionState == .connecting)
        }
        .padding(18)
        .frame(minHeight: 235, alignment: .top)
    }
}

private struct ActivityList: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Group {
            if model.activities.isEmpty {
                ContentUnavailableView(
                    "All quiet",
                    systemImage: "checkmark.circle",
                    description: Text("Unsettled threads will appear here.")
                )
                .frame(height: 260)
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        Label("\(model.activeCount) working", systemImage: "bolt.fill")
                            .foregroundStyle(.blue)
                        if model.approvalCount > 0 {
                            Label(
                                model.approvalCount == 1 ? "1 approval" : "\(model.approvalCount) approvals",
                                systemImage: "checkmark.shield.fill"
                            )
                                .foregroundStyle(.orange)
                                .help("Waiting for approval")
                        }
                        Label("\(model.doneCount) done", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        Spacer()
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.activities) { activity in
                                ActivityRow(activity: activity) {
                                    model.open(activity)
                                }
                            }
                        }
                        .padding(10)
                    }
                    .frame(height: 325)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let activity: AgentActivity
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                ActivityRail(phase: activity.displayPhase)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(activity.threadTitle)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 6)
                        Text(activity.updatedAt, style: .relative)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }

                    HStack(spacing: 6) {
                        Text(activity.projectTitle)
                            .lineLimit(1)
                        Text("·")
                        Text(activity.modelTitle)
                            .lineLimit(1)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    HStack(spacing: 6) {
                        Image(systemName: activity.displayPhase.symbol)
                        Text(activity.statusLabel)
                            .lineLimit(1)
                        if let detail = activity.statusDetail {
                            Text("· \(detail)")
                                .lineLimit(1)
                        }
                        if let progress = activity.planProgress {
                            Text("\(progress.completedSteps)/\(progress.totalSteps)")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(activity.displayPhase.color)
                }
            }
            .padding(10)
            .contentShape(Rectangle())
            .background(activity.displayPhase.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct ActivityRail: View {
    let phase: ActivityPhase

    var body: some View {
        VStack(spacing: 4) {
            Circle()
                .fill(phase.color)
                .frame(width: 8, height: 8)
            Capsule()
                .fill(phase.color.opacity(0.45))
                .frame(width: 3)
        }
        .frame(width: 8)
    }
}

private struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.title3.weight(.semibold))

            Toggle("Native notifications", isOn: Binding(
                get: { model.notificationsEnabled },
                set: { model.setNotificationsEnabled($0) }
            ))

            VStack(alignment: .leading, spacing: 8) {
                Text("Menu-bar number")
                    .font(.callout.weight(.medium))
                Toggle("Working", isOn: Binding(
                    get: { model.menuBarCountMode.includesWorking },
                    set: { model.setCountsWorking($0) }
                ))
                Toggle("Done", isOn: Binding(
                    get: { model.menuBarCountMode.includesDone },
                    set: { model.setCountsDone($0) }
                ))
                Text("Done means observed work stopped and has not been opened from this menu.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle("Launch at login", isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))

            if let connection = model.connection {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paired environment")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(connection.label)
                        .font(.callout.weight(.medium))
                    Text(connection.baseURL.host() ?? connection.baseURL.absoluteString)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            Button("Disconnect", role: .destructive) {
                model.disconnect()
            }
        }
        .padding(18)
        .frame(height: 390, alignment: .top)
    }
}

private struct ErrorBanner: View {
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.08))
    }
}

private struct Footer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 4) {
            if model.connection != nil {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Refresh now")

                if let updated = model.lastUpdated {
                    (Text("Updated ") + Text(updated, style: .relative))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
            if model.connection != nil {
                Button {
                    model.showsSettings.toggle()
                } label: {
                    Label(model.showsSettings ? "Activity" : "Settings", systemImage: model.showsSettings ? "list.bullet" : "gearshape")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help(model.showsSettings ? "Show activity" : "Settings")
            }
            Button("Quit") { model.quit() }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }
}

private extension ActivityPhase {
    var label: String {
        switch self {
        case .idle: "Idle"
        case .starting: "Starting"
        case .running: "Working"
        case .waitingForApproval: "Approval needed"
        case .waitingForInput: "Input needed"
        case .done: "Done"
        case .failed: "Failed"
        }
    }

    var symbol: String {
        switch self {
        case .idle: "circle.fill"
        case .starting: "clock.fill"
        case .running: "bolt.fill"
        case .waitingForApproval: "checkmark.shield.fill"
        case .waitingForInput: "text.bubble.fill"
        case .done: "checkmark.circle.fill"
        case .failed: "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: .secondary
        case .starting: .cyan
        case .running: .blue
        case .waitingForApproval, .waitingForInput: .orange
        case .done: .green
        case .failed: .red
        }
    }

    var tint: Color {
        switch self {
        case .waitingForApproval, .waitingForInput, .failed: color.opacity(0.08)
        default: Color.primary.opacity(0.025)
        }
    }
}

private extension AgentActivity {
    var displayPhase: ActivityPhase {
        needsReview ? .done : phase
    }

    var statusLabel: String {
        if needsReview { return "Done" }
        return phase == .done ? "Finished" : phase.label
    }

    var statusDetail: String? {
        needsReview ? "Ready to review" : detail
    }
}
