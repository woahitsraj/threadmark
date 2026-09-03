import SwiftUI
import ThreadmarkCore

struct MenuPanel: View {
    @ObservedObject var model: AppModel
    let updater: AppUpdater

    var body: some View {
        VStack(spacing: 0) {
            Header(model: model)
            Divider()

            if model.connection == nil {
                PairingView(model: model)
            } else if model.showsSettings {
                SettingsView(model: model, updater: updater)
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
                Text("Create an interactive pairing link in T3 Code, then paste it here. Threadmark requests read and orchestration control access. The revocable credential is kept in Keychain.")
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
                        if model.doneCount > 0 {
                            Button {
                                model.markAllAsRead()
                            } label: {
                                Label("Mark all as read", systemImage: "checkmark.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                            .help("Clear unreviewed completions and delivered notifications")
                        }
                    }
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)

                    Divider()

                    ScrollView {
                        LazyVStack(spacing: 7) {
                            ForEach(model.activities) { activity in
                                ActivityRow(activity: activity, model: model)
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
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Button { model.open(activity) } label: {
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
            }
            .buttonStyle(.plain)

            interaction
        }
        .padding(10)
        .contentShape(Rectangle())
        .background(activity.displayPhase.tint, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 0.5)
        }
    }

    @ViewBuilder
    private var interaction: some View {
        if activity.phase == .waitingForApproval,
           let approval = activity.interactions.approvals.first {
            if model.canInteract {
                ApprovalControls(activity: activity, approval: approval, model: model)
            } else {
                LockedControls()
            }
        } else if activity.phase == .waitingForInput,
                  let input = activity.interactions.userInputs.first {
            if model.canInteract {
                UserInputControls(activity: activity, input: input, model: model)
                    .id(input.requestId)
            } else {
                LockedControls()
            }
        } else if [.idle, .done, .failed].contains(activity.phase) {
            if model.canInteract {
                ReplyControls(activity: activity, model: model)
            } else if activity.needsReview || activity.phase == .failed {
                LockedControls()
            }
        }
    }
}

private struct LockedControls: View {
    var body: some View {
        Label("Reconnect with interactive access to respond here", systemImage: "lock.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
    }
}

private struct ApprovalControls: View {
    let activity: AgentActivity
    let approval: PendingApproval
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if let detail = approval.detail, !detail.isEmpty {
                Text(detail)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .textSelection(.enabled)
            }
            HStack(spacing: 7) {
                ForEach(primaryOptions, id: \.decision) { option in
                    Button(option.label) {
                        Task { await model.respondToApproval(
                            in: activity,
                            requestId: approval.requestId,
                            decision: option.decision
                        ) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if !otherOptions.isEmpty {
                    Menu {
                        ForEach(otherOptions, id: \.decision) { option in
                            Button(option.label) {
                                Task { await model.respondToApproval(
                                    in: activity,
                                    requestId: approval.requestId,
                                    decision: option.decision
                                ) }
                            }
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
                Spacer()
            }
        }
    }

    private var primaryOptions: [ApprovalOption] {
        let options = approval.availableOptions
        return [
            options.first { $0.decision == .accept },
            options.first { $0.decision == .decline },
        ].compactMap { $0 }
    }

    private var otherOptions: [ApprovalOption] {
        approval.availableOptions.filter { option in
            !primaryOptions.contains { $0.decision == option.decision }
        }
    }
}

private struct ReplyControls: View {
    let activity: AgentActivity
    @ObservedObject var model: AppModel
    @State private var reply = ""

    var body: some View {
        HStack(spacing: 7) {
            TextField("Reply to this thread", text: $reply)
                .textFieldStyle(.roundedBorder)
                .onSubmit(send)
            Button("Send", action: send)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func send() {
        let text = reply
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        Task {
            if await model.reply(to: activity, text: text) {
                reply = ""
            }
        }
    }
}

private struct UserInputControls: View {
    let activity: AgentActivity
    let input: PendingUserInput
    @ObservedObject var model: AppModel
    @State private var selections: [String: Set<String>] = [:]
    @State private var customAnswers: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(input.questions, id: \.id) { question in
                VStack(alignment: .leading, spacing: 5) {
                    Text(question.header)
                        .font(.caption.weight(.semibold))
                    Text(question.question)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if question.multiSelect {
                        ForEach(question.options, id: \.label) { option in
                            Toggle(isOn: choiceBinding(question: question, label: option.label)) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(option.label)
                                    if option.description != option.label {
                                        Text(option.description)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                            .font(.caption)
                        }
                    } else {
                        Picker("", selection: singleChoiceBinding(question: question)) {
                            Text("Choose…").tag("")
                            ForEach(question.options, id: \.label) { option in
                                Text(option.label).tag(option.label)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                    TextField("Other answer", text: customBinding(question.id))
                        .textFieldStyle(.roundedBorder)
                        .font(.caption)
                }
            }
            HStack {
                Spacer()
                Button("Submit answers") {
                    Task { await model.respondToUserInput(
                        in: activity,
                        requestId: input.requestId,
                        answers: answers
                    ) }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(answers.count != input.questions.count)
            }
        }
    }

    private var answers: [String: UserInputAnswer] {
        Dictionary(uniqueKeysWithValues: input.questions.compactMap { question in
            if let custom = customAnswers[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !custom.isEmpty {
                return (question.id, .text(custom))
            }
            let selected = Array(selections[question.id] ?? []).sorted()
            guard !selected.isEmpty else { return nil }
            return question.multiSelect
                ? (question.id, .choices(selected))
                : (question.id, .text(selected[0]))
        })
    }

    private func customBinding(_ questionId: String) -> Binding<String> {
        Binding(
            get: { customAnswers[questionId, default: ""] },
            set: {
                customAnswers[questionId] = $0
                if !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    selections[questionId] = []
                }
            }
        )
    }

    private func singleChoiceBinding(question: UserInputQuestion) -> Binding<String> {
        Binding(
            get: { selections[question.id]?.first ?? "" },
            set: {
                selections[question.id] = $0.isEmpty ? [] : [$0]
                if !$0.isEmpty { customAnswers[question.id] = "" }
            }
        )
    }

    private func choiceBinding(question: UserInputQuestion, label: String) -> Binding<Bool> {
        Binding(
            get: { selections[question.id]?.contains(label) == true },
            set: { selected in
                var values = selections[question.id] ?? []
                if selected { values.insert(label) } else { values.remove(label) }
                selections[question.id] = values
                if selected { customAnswers[question.id] = "" }
            }
        )
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
    let updater: AppUpdater

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

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .disabled(!updater.isConfigured)
            .help(updater.isConfigured ? "Check for a newer Threadmark release" : "Updates are unavailable in this development build")

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
                    Label(
                        connection.canOperate ? "Interactive access" : "Read-only access",
                        systemImage: connection.canOperate ? "checkmark.shield.fill" : "lock.fill"
                    )
                    .font(.caption)
                    .foregroundStyle(connection.canOperate ? .green : .secondary)
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
