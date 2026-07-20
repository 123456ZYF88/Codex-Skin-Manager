import Darwin
import Foundation

@main
enum CodexSkinManagerTestMain {
    static func main() async {
        do {
            try ThemeCatalogTests.run()
            try await EngineBridgeTests.run()
            try ThemeLibraryQueryTests.run()
            try await AppModelTests.run()
            try await UICompileTests.run()
            print("PASS: all Codex Skin Manager tests")
        } catch {
            fputs("FAIL: \(error)\n", stderr)
            exit(1)
        }
    }
}
