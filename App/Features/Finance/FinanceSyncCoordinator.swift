import Observation

@MainActor
@Observable
final class FinanceSyncCoordinator {
  private(set) var isLoading = false
  private var active: Task<Void, Never>?
  private var generation = 0

  func refresh(_ operations: [@MainActor () async -> Void]) async {
    if let active { await active.value; return }
    generation &+= 1
    let request = generation
    isLoading = true
    let task = Task { @MainActor in
      await withTaskGroup(of: Void.self) { group in
        for operation in operations { group.addTask { await operation() } }
      }
    }
    active = task
    // A view disappearing must not cancel a refresh shared with other screens.
    await task.value
    if generation == request { active = nil; isLoading = false }
  }

  func cancel() { generation &+= 1; active?.cancel(); active = nil; isLoading = false }
}
