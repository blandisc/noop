import SwiftUI
import StrandDesign

/// Coach — «Pregúntale a tus datos», the one feature in NOOP that talks to the network.
///
/// Strictly opt-in and bring-your-own-key: the user pastes their own OpenAI or Anthropic API key
/// (stored in the device Keychain by `AICoachEngine`), and only a compact text summary of their
/// metrics plus their question ever leaves the device. Nothing is sent until a key is saved and a
/// question asked.
///
/// Rendered in «Instrumento diurno» (FER-309): warm paper, ink type, color only on a datum. The
/// network capability (`AICoachEngine`, Keychain, consent) is unchanged — only the skin. Opened as a
/// light sheet from the Bucle (theme injected at the sheet root, FER-162).
///
/// Compiles against `AICoachEngine`'s public API: `hasKey`, `provider` / `provider.modelOptions`,
/// `model`, `messages`, `sending`, `errorText`, `setKey(_:)`, `clearKey()`, and `send(_:)`.
struct CoachView: View {
    @EnvironmentObject var coach: AICoachEngine
    @Environment(\.instrumentoTheme) private var theme

    /// Draft text in the composer (the question being typed).
    @State private var draft: String = ""
    /// Pending key text in the setup card (never persisted here — handed to `setKey`).
    @State private var keyDraft: String = ""
    /// Whether the model selector is in free-text "Custom…" mode.
    @State private var customModel: Bool = false
    /// The id typed in the "Custom…" field.
    @State private var customModelDraft: String = ""
    @FocusState private var composerFocused: Bool

    /// Sentinel tag for the "Custom…" entry in the model Picker.
    private let customModelTag = "__custom__"

    private let suggestions = [
        String(localized: "How's my recovery trending?"),
        String(localized: "What should today's training look like?"),
        String(localized: "Analyse my sleep"),
        String(localized: "Why am I run down?"),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: CenitMetrics.sectionGap) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Coach").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Text("Pregúntale a tus datos").font(StrandFont.title1).foregroundStyle(theme.ink)
                }
                if coach.hasKey {
                    connectedHeader
                    consentBar
                    transcript
                    if let error = coach.errorText, !error.isEmpty {
                        errorBanner(error)
                    }
                    suggestionChips
                    composer
                    privacyFootnote
                } else {
                    setupCard
                }
            }
            .padding(CenitMetrics.screenPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(theme.paper.ignoresSafeArea())
        .task(id: coach.dataConsent) { await coach.startBriefIfNeeded() }
    }

    /// Explicit, revocable permission for the coach to read & send the user's data. Off by default.
    private var consentBar: some View {
        HStack(spacing: 10) {
            Image(systemName: coach.dataConsent ? "lock.open.fill" : "lock.fill")
                .foregroundStyle(coach.dataConsent ? theme.dataRecovery : theme.inkTertiary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text("Let the coach use my data")
                    .font(StrandFont.subhead).foregroundStyle(theme.ink)
                Text(coach.dataConsent
                     ? "On: your recovery, sleep, HRV and workouts are shared with the provider for tailored coaching."
                     : "Off: the coach answers generally and sends none of your metrics.")
                    .font(StrandFont.footnote).foregroundStyle(theme.inkTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: $coach.dataConsent)
                .labelsHidden().toggleStyle(.instrumento)
                .accessibilityLabel("Let the coach use my data")
        }
        .padding(12)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
            .strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }

    // MARK: - Setup (no key yet)

    private var setupCard: some View {
        card {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 10) {
                    Image(systemName: "sparkles")
                        .foregroundStyle(theme.inkSecondary)
                        .accessibilityHidden(true)
                    Text("Connect a provider")
                        .font(StrandFont.headline)
                        .foregroundStyle(theme.ink)
                }

                Text("Coach uses your own API key. Pick a provider, paste a key, and choose a model. Your key is stored securely in the device Keychain and never leaves your phone except as the request you make.")
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                // Provider
                VStack(alignment: .leading, spacing: 6) {
                    Text("Provider").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    Picker("Provider", selection: $coach.provider) {
                        ForEach(AIProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Provider")
                }

                // Model
                modelSelector

                // Key
                VStack(alignment: .leading, spacing: 6) {
                    Text("API key").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                    SecureField("Paste your \(coach.provider.displayName) API key", text: $keyDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .instrumentoCard(.inset, theme: theme, fill: theme.surface, stroke: theme.hairlineStrong)
                        .onSubmit(saveKey)
                        .accessibilityLabel("API key")
                }

                HStack {
                    inkButton("Save key", action: saveKey,
                              disabled: keyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Spacer()
                }

                Divider().overlay(theme.hairline)
                privacyFootnote
            }
        }
    }

    /// Model selector: a Picker over `coach.availableModels` with a free-text "Custom…" path and a
    /// "Refresh models" button that fetches the provider's live list.
    private var modelSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Model").instrumentoOverline().foregroundStyle(theme.inkTertiary)
                Spacer()
                Button {
                    Task { await coach.refreshModels() }
                } label: {
                    Label("Refresh models", systemImage: "arrow.clockwise")
                        .font(StrandFont.footnote)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.plain)
                .foregroundStyle(theme.inkSecondary)
                .disabled(!coach.hasKey)
                .accessibilityLabel("Refresh models from provider")
            }

            Picker("Model", selection: modelPickerSelection) {
                ForEach(coach.availableModels, id: \.self) { m in
                    Text(m).tag(m)
                }
                Divider()
                Text("Custom…").tag(customModelTag)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .tint(theme.ink)
            .fixedSize()
            .accessibilityLabel("Model")

            if customModel {
                HStack(spacing: 8) {
                    TextField("Enter a model id", text: $customModelDraft)
                        .textFieldStyle(.plain)
                        .font(StrandFont.body)
                        .foregroundStyle(theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .instrumentoCard(.inset, theme: theme, fill: theme.surface, stroke: theme.hairlineStrong)
                        .onSubmit(applyCustomModel)
                        .accessibilityLabel("Custom model id")

                    inkButton("Use", action: applyCustomModel,
                              disabled: customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityLabel("Use custom model")
                }
            }
        }
    }

    /// Bridges the model Picker to `coach.model`, with a "Custom…" sentinel that opens the free-text
    /// field instead of selecting a real id.
    private var modelPickerSelection: Binding<String> {
        Binding(
            get: { customModel ? customModelTag : coach.model },
            set: { newValue in
                if newValue == customModelTag {
                    customModel = true
                    if customModelDraft.isEmpty { customModelDraft = coach.model }
                } else {
                    customModel = false
                    coach.model = newValue
                }
            }
        )
    }

    private func applyCustomModel() {
        let trimmed = customModelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setCustomModel(trimmed)
        customModel = false
    }

    // MARK: - Connected state

    private var connectedHeader: some View {
        HStack(spacing: 10) {
            Text("\(coach.provider.displayName) · \(coach.model)")
                .font(StrandFont.captionNumber)
                .foregroundStyle(theme.inkSecondary)
                .padding(.horizontal, 10).padding(.vertical, 4)
                .overlay(Capsule().stroke(theme.hairlineStrong, lineWidth: 1))
            if coach.sending {
                Text("Pensando…").font(StrandFont.captionNumber).foregroundStyle(theme.inkTertiary)
            }
            Spacer()
            Button {
                coach.clearKey()
                keyDraft = ""
            } label: {
                Text("Quitar clave").font(StrandFont.footnote).foregroundStyle(theme.critical)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Reset API key")
        }
    }

    private var transcript: some View {
        card(padding: 16) {
            if coach.messages.isEmpty {
                emptyTranscript
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(coach.messages) { message in
                                bubble(message).id(message.id)
                            }
                            if coach.sending {
                                typingIndicator.id("typing")
                            }
                        }
                        .padding(.vertical, 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(minHeight: 220, maxHeight: 460)
                    .onChange(of: coach.messages.count) {
                        scrollToEnd(proxy)
                    }
                    .onChange(of: coach.sending) {
                        scrollToEnd(proxy)
                    }
                }
            }
        }
    }

    private var emptyTranscript: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Ask your first question")
                .font(StrandFont.headline)
                .foregroundStyle(theme.ink)
            Text("Coach reads a summary of your last two weeks plus 30-day averages and recent workouts, then answers in plain language. Try a suggestion below.")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
    }

    @ViewBuilder
    private func bubble(_ message: ChatMessage) -> some View {
        switch message.role {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .instrumentoCard(.cta, theme: theme, fill: theme.surface, stroke: theme.hairlineStrong)
                    .frame(maxWidth: 520, alignment: .trailing)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("You said: \(message.text)")
        case .assistant:
            HStack {
                Text(message.text)
                    .font(StrandFont.body)
                    .foregroundStyle(theme.ink)
                    .textSelection(.enabled)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 560, alignment: .leading)
                Spacer(minLength: 48)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Coach said: \(message.text)")
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text("Coach is thinking…")
                .font(StrandFont.subhead)
                .foregroundStyle(theme.inkSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .accessibilityLabel("Coach is thinking")
    }

    private func errorBanner(_ message: String) -> some View {
        card(padding: 14) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(theme.critical)
                    .accessibilityHidden(true)
                Text(message)
                    .font(StrandFont.subhead)
                    .foregroundStyle(theme.critical)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Error: \(message)")
    }

    private var suggestionChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { prompt in
                    Button {
                        send(prompt)
                    } label: {
                        Text(prompt)
                            .font(StrandFont.captionNumber)
                            .foregroundStyle(theme.inkSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(theme.surface, in: Capsule(style: .continuous))
                            .overlay(Capsule(style: .continuous).strokeBorder(theme.hairlineStrong, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .disabled(coach.sending)
                    .accessibilityLabel("Suggested prompt: \(prompt)")
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Ask Coach about your data…", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(StrandFont.body)
                .foregroundStyle(theme.ink)
                .lineLimit(1...5)
                .focused($composerFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .instrumentoCard(.control, theme: theme, fill: theme.surface, stroke: composerFocused ? theme.ink.opacity(StrandOpacity.dim) : theme.hairlineStrong)
                .onSubmit { send(draft) }
                .accessibilityLabel("Question")

            Button {
                send(draft)
            } label: {
                Group {
                    if coach.sending {
                        ProgressView().controlSize(.small).tint(theme.paper)
                    } else {
                        Image(systemName: "arrow.up").font(StrandFont.glyph(.inline, weight: .semibold))
                    }
                }
                .frame(width: 44, height: 36)
                .foregroundStyle(theme.paper)
                .background(sendDisabled ? theme.inkTertiary : theme.ink,
                            in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous)) // token-exempt: fondo condicional
            }
            .buttonStyle(.plain)
            .disabled(sendDisabled)
            .accessibilityLabel("Send")
        }
    }

    private var sendDisabled: Bool {
        coach.sending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var privacyFootnote: some View {
        Label {
            Text("This is the only feature that leaves your phone: it sends a summary of your metrics to \(coach.provider.displayName) using your own key. Nothing is sent until you ask.")
                .font(StrandFont.footnote)
                .foregroundStyle(theme.inkTertiary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "lock.shield")
                .foregroundStyle(theme.inkTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Instrumento building blocks

    /// A warm-paper card: surface fill + hairline border, no nesting. Replaces the legacy dark StrandCard.
    @ViewBuilder private func card<Content: View>(padding: CGFloat = 20,
                                                  @ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: CenitMetrics.cardRadius, style: .continuous)
                .strokeBorder(theme.hairlineStrong, lineWidth: 1))
    }

    /// A sober ink-filled CTA (the one prominent action; chrome otherwise stays quiet).
    private func inkButton(_ title: LocalizedStringKey, action: @escaping () -> Void,
                           disabled: Bool) -> some View {
        Button(action: action) {
            Text(title).font(StrandFont.subhead).fontWeight(.medium)
                .foregroundStyle(theme.paper)
                .frame(minWidth: 90)
                .padding(.horizontal, 16).padding(.vertical, 9)
                .background(disabled ? theme.inkTertiary : theme.ink,
                            in: RoundedRectangle(cornerRadius: CenitMetrics.controlRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: - Actions

    private func saveKey() {
        let trimmed = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        coach.setKey(trimmed)
        keyDraft = ""
    }

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !coach.sending else { return }
        draft = ""
        composerFocused = false
        Task { await coach.send(trimmed) }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(StrandMotion.fade) {
            if coach.sending {
                proxy.scrollTo("typing", anchor: .bottom)
            } else if let last = coach.messages.last {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }
}
