import SwiftUI

struct MCPApprovalView: View {
  var request: MCPAccessStore.Request
  var decide: (MCPAccessStore.Decision) -> Void

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          Text("The on-device assistant wants to contact Sure. Automatic MCP access is off.")
          LabeledContent("Server", value: request.server.absoluteString)
          LabeledContent("Operation", value: request.operation)
          Text("Arguments sent to Sure")
            .font(.headline)
            .accessibilityAddTraits(.isHeader)
          Text(request.arguments)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
          Text("Allow Once approves only this operation. Always Allow enables read-only MCP access on this device. You can turn it off in Assistant settings.")
            .font(.footnote)
            .foregroundStyle(.secondary)
          Button("Allow Once") { decide(.allowOnce) }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("mcp-allow-once")
          Button("Always Allow on This Device") { decide(.alwaysAllow) }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("mcp-always-allow")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
      .navigationTitle("Allow Sure MCP Access?")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel", role: .cancel) { decide(.cancel) }
        }
      }
    }
  }
}
