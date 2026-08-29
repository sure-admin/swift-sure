import SwiftUI

struct AssistantView: View {
  @Environment(\.showConnectionSettings) private var showConnectionSettings
  var connection: SureConnection
  @State private var store: AssistantStore
  @State private var sureSendHaptic = 0
  @State private var didLongPressSend = false

  init(
    connection: SureConnection,
    financeData: FinanceDataStore,
    remoteAssistant: any RemoteAssistantClient,
    makeMessageID: @escaping () -> UUID,
    now: @escaping () -> Date
  ) {
    self.connection = connection
    _store = State(
      initialValue: AssistantStore(
        connection: connection,
        remoteAssistant: remoteAssistant,
        localAssistant: LocalAssistantService(financeData: financeData),
        makeID: makeMessageID,
        now: now
      )
    )
  }

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        GeometryReader { geometry in
          ScrollViewReader { proxy in
            ScrollView {
              VStack(spacing: 14) {
                suggestionCard
                Spacer(minLength: 32)
                conversation
              }
              .frame(maxWidth: 760)
              .frame(maxWidth: .infinity)
              .frame(minHeight: max(0, geometry.size.height - 32))
              .padding()
            }
            .onChange(of: store.messages.count) {
              if let last = store.messages.last {
                withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
              }
            }
          }
        }
        composer
      }
      .background(SureTheme.canvas.opacity(0.65))
      .navigationTitle("Assistant")
      .toolbar {
        ToolbarItem(placement: .primaryAction) {
          Button("Connection settings", systemImage: "gearshape") {
            showConnectionSettings()
          }
        }
      }
      .onChange(of: connection.hasVerifiedAPIKey, initial: true) { _, hasVerifiedAPIKey in
        store.updateConnectionPrompts(hasVerifiedAPIKey: hasVerifiedAPIKey)
      }
    }
  }

  private var suggestionCard: some View {
    VStack(alignment: .leading, spacing: 12) {
      Label("Try asking", systemImage: "sparkles")
        .font(.headline)
      suggestion("💸 Where did my money go?")
      suggestion("✈️ Can I afford a trip?")
      suggestion("🔁 Find recurring costs")
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .sureCard()
  }

  private var conversation: some View {
    LazyVStack(spacing: 14) {
      ForEach(store.messages) { message in
        messageBubble(message)
          .id(message.id)
      }
      if store.isResponding {
        HStack {
          ProgressView()
          Text("Thinking…")
            .foregroundStyle(.secondary)
          Spacer()
        }
      }
      if let errorMessage = store.errorMessage {
        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
          .font(.footnote)
          .foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func suggestion(_ text: String) -> some View {
    Button(text) {
      store.draft = text
      submit(to: .localModel)
    }
    .buttonStyle(.bordered)
    .fixedSize(horizontal: true, vertical: false)
  }

  private func messageBubble(_ message: AssistantMessage) -> some View {
    HStack {
      if message.role == .user { Spacer(minLength: 40) }
      messageContent(message)
        .textSelection(.enabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
          message.role == .user ? SureTheme.ink : Color.primary.opacity(0.07),
          in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .foregroundStyle(message.role == .user ? .white : .primary)
      if message.role == .assistant { Spacer(minLength: 40) }
    }
    .accessibilityElement(children: .combine)
    .accessibilityLabel("\(message.role == .user ? "You" : "Sure Assistant"): \(accessibleContent(message.content))")
  }

  @ViewBuilder
  private func messageContent(_ message: AssistantMessage) -> some View {
    if message.role == .assistant {
      MarkdownText(source: message.content)
    } else {
      Text(message.content)
    }
  }

  private func accessibleContent(_ markdown: String) -> String {
    guard let attributedContent = try? AttributedString(markdown: markdown) else { return markdown }
    return String(attributedContent.characters)
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Ask about your finances", text: $store.draft, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onSubmit { submit(to: .localModel) }
      Button {
        guard !didLongPressSend else {
          didLongPressSend = false
          return
        }
        submit(to: .localModel)
      } label: {
        Label("Send", systemImage: "arrow.up")
          .labelStyle(.iconOnly)
          .font(.headline)
          .frame(width: 44, height: 44)
          .background(SureTheme.accent, in: Circle())
          .foregroundStyle(SureTheme.ink)
      }
      .buttonStyle(.plain)
      .simultaneousGesture(
        LongPressGesture(minimumDuration: 0.6)
          .onEnded { _ in
            didLongPressSend = true
            sureSendHaptic += 1
            submit(to: .sureServer)
          }
      )
      .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isResponding)
      .sensoryFeedback(.impact(weight: .heavy), trigger: sureSendHaptic)
      .accessibilityHint("Tap for an on-device answer. Touch and hold to send to Sure.")
    }
    .padding()
    .background(.bar)
  }

  private func submit(to destination: AssistantDestination) {
    if destination == .sureServer && !connection.isConfigured {
      showConnectionSettings()
      return
    }
    Task { await store.send(to: destination) }
  }
}
