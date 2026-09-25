import Darwin
import Foundation

struct FinanceKitProcessLock: Sendable {
  var url: URL

  func acquire() throws -> Token {
    let directory = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let descriptor = open(url.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard descriptor >= 0 else {
      throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      if errno == EWOULDBLOCK {
        close(descriptor)
        throw FinanceKitProcessLockError.busy
      }
      let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
      close(descriptor)
      throw error
    }
    return Token(descriptor: descriptor)
  }

  final class Token: @unchecked Sendable {
    private var descriptor: Int32

    fileprivate init(descriptor: Int32) {
      self.descriptor = descriptor
    }

    deinit {
      guard descriptor >= 0 else { return }
      flock(descriptor, LOCK_UN)
      close(descriptor)
      descriptor = -1
    }
  }
}

enum FinanceKitProcessLockError: Error {
  case busy
}
