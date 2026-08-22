import SwiftUI

struct AssistantView: View {
  @State private var store = AssistantStore()
  @State private var showingConnection = false

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        ScrollViewReader { proxy in
          ScrollView {
            LazyVStack(spacing: 14) {
              suggestionStrip
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
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
            .padding()
          }
          .onChange(of: store.messages.count) {
            if let last = store.messages.last {
              withAnimation(.smooth) { proxy.scrollTo(last.id, anchor: .bottom) }
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
            showingConnection = true
          }
        }
      }
      .sheet(isPresented: $showingConnection) {
        ConnectionSettingsView()
      }
    }
  }

  private var suggestionStrip: some View {
    ScrollView(.horizontal) {
      HStack {
        suggestion("Where did my money go?")
        suggestion("Can I afford a trip?")
        suggestion("Find recurring costs")
      }
    }
    .scrollIndicators(.hidden)
  }

  private func suggestion(_ text: String) -> some View {
    Button(text) {
      store.draft = text
      Task { await store.send() }
    }
    .buttonStyle(.bordered)
  }

  private func messageBubble(_ message: AssistantMessage) -> some View {
    HStack {
      if message.role == .user { Spacer(minLength: 40) }
      Text(message.content)
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
    .accessibilityLabel(message.role == .user ? "You" : "Sure Assistant")
  }

  private var composer: some View {
    HStack(alignment: .bottom, spacing: 10) {
      TextField("Ask about your finances", text: $store.draft, axis: .vertical)
        .lineLimit(1...5)
        .textFieldStyle(.plain)
        .padding(12)
        .background(.background, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onSubmit { Task { await store.send() } }
      Button("Send", systemImage: "arrow.up") {
        Task { await store.send() }
      }
      .labelStyle(.iconOnly)
      .font(.headline)
      .frame(width: 44, height: 44)
      .background(SureTheme.accent, in: Circle())
      .foregroundStyle(SureTheme.ink)
      .disabled(store.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isResponding)
    }
    .padding()
    .background(.bar)
  }
}
