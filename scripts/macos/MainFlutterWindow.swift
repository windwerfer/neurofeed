import Cocoa
import FlutterMacOS

private final class SandboxBookmarks {
  static let shared = SandboxBookmarks()
  private var accessed: [URL] = []

  func bookmark(path: String) throws -> String {
    let url = URL(fileURLWithPath: path, isDirectory: true)
    let data = try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    return data.base64EncodedString()
  }

  func activate(bookmark: String) throws -> [String: String] {
    guard let data = Data(base64Encoded: bookmark) else {
      throw BookmarkError.badEncoding
    }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    if !url.startAccessingSecurityScopedResource() {
      throw BookmarkError.accessDenied
    }
    accessed.append(url)
    var stored = bookmark
    if stale {
      let fresh = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      stored = fresh.base64EncodedString()
    }
    return ["path": url.path, "bookmark": stored]
  }
}

private enum BookmarkError: Error {
  case badEncoding
  case accessDenied
}

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "neurofeed/mac_sandbox",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "bookmark":
        guard let path = args?["path"] as? String, !path.isEmpty else {
          result(FlutterError(code: "bad_args", message: "path required", details: nil))
          return
        }
        do {
          result(try SandboxBookmarks.shared.bookmark(path: path))
        } catch {
          result(FlutterError(code: "bookmark", message: "\(error)", details: nil))
        }
      case "activate":
        guard let bookmark = args?["bookmark"] as? String, !bookmark.isEmpty else {
          result(FlutterError(code: "bad_args", message: "bookmark required", details: nil))
          return
        }
        do {
          result(try SandboxBookmarks.shared.activate(bookmark: bookmark))
        } catch {
          result(FlutterError(code: "bookmark", message: "\(error)", details: nil))
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }
}
