import CleanMyMacCore
import Foundation

struct CleanupResult: Sendable {
    let removedTargets: Int
    let blockedTargets: Int
    let failedTargets: Int
    let freedBytes: UInt64

    var summary: String {
        let freed = ByteCountFormatter.string(fromByteCount: Int64(freedBytes), countStyle: .file)
        if failedTargets > 0 {
            return "\(freed) liberados; \(failedTargets) falhas verificadas. Nova tentativa agendada."
        }
        if blockedTargets > 0 {
            return "\(freed) liberados; \(blockedTargets) projetos ativos preservados."
        }
        return "\(freed) liberados com segurança."
    }
}

enum SafeCleaner {
    static let logURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Logs/CleanMyMac/clean-my-mac.log")

    private static let home = FileManager.default.homeDirectoryForCurrentUser
    private static var protectedPaths: [String] {
        [
            "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies",
            "Music", "Pictures", "Public", "Arquivos Públicos", "Arquivos Públicos", ".Trash",
        ].map { home.appending(path: $0).path }
    }
    private static let minimumArtifactKiB = 100 * 1024

    static func run() async -> CleanupResult {
        await Task.detached(priority: .utility) {
            runSynchronously()
        }.value
    }

    static func prepareLog() {
        CleanupLog(url: logURL).append("MONITOR app iniciado")
    }

    static func record(_ message: String) {
        CleanupLog(url: logURL).append(message)
    }

    private static func runSynchronously() -> CleanupResult {
        let before = (try? StorageReader.read().availableBytes) ?? 0
        var removedTargets = 0
        var blockedTargets = 0
        var failedTargets = 0
        let log = CleanupLog(url: logURL)
        log.append("START armazenamento seguro")

        cleanNativeCaches(log: log)
        let artifactResult = cleanGeneratedArtifacts(log: log)
        removedTargets += artifactResult.removed
        blockedTargets += artifactResult.blocked
        failedTargets += artifactResult.failed
        let after = (try? StorageReader.read().availableBytes) ?? before
        let freed = after > before ? after - before : 0
        log.append("END liberados=\(freed) removidos=\(removedTargets) bloqueados=\(blockedTargets) falhas=\(failedTargets)")
        return CleanupResult(
            removedTargets: removedTargets,
            blockedTargets: blockedTargets,
            failedTargets: failedTargets,
            freedBytes: freed
        )
    }

    private static func cleanNativeCaches(log: CleanupLog) {
        let commands: [([String], [String])] = [
            ([home.appending(path: ".local/bin/uv").path, "/opt/homebrew/bin/uv", "/usr/local/bin/uv"], ["cache", "clean"]),
            (["/opt/homebrew/bin/npm", "/usr/local/bin/npm"], ["cache", "clean", "--force"]),
            ([home.appending(path: ".bun/bin/bun").path, "/opt/homebrew/bin/bun", "/usr/local/bin/bun"], ["pm", "cache", "rm"]),
            (["/opt/homebrew/bin/deno", "/usr/local/bin/deno"], ["clean"]),
            (["/opt/homebrew/bin/brew", "/usr/local/bin/brew"], ["cleanup", "-s", "--prune=all"]),
        ]

        for (locations, arguments) in commands {
            guard let executable = locations.first(where: FileManager.default.isExecutableFile(atPath:)) else { continue }
            let result = run(executable, arguments)
            log.append("CACHE \(executable) exit=\(result.code) \(result.output)")
        }
    }

    private static func cleanGeneratedArtifacts(log: CleanupLog) -> (removed: Int, blocked: Int, failed: Int) {
        let sizedCandidates = artifactCandidates().compactMap { candidate -> (URL, Int)? in
            let result = run("/usr/bin/du", ["-sk", candidate.path])
            guard result.code == 0,
                  let first = result.output.split(whereSeparator: { $0.isWhitespace }).first,
                  let size = Int(first),
                  CleanupPolicy.isEligibleArtifact(
                      name: candidate.lastPathComponent,
                      sizeKiB: size,
                      isSymbolicLink: false,
                      minimumKiB: minimumArtifactKiB
                  ) else { return nil }
            return (candidate, size)
        }.sorted { $0.1 > $1.1 }

        var removed = 0
        var blocked = 0
        var failed = 0

        for (target, sizeKiB) in sizedCandidates {
            guard let gitRoot = gitRoot(for: target) else {
                log.append("SKIP sem Git: \(target.path)")
                continue
            }
            guard run("/usr/bin/git", ["-C", gitRoot.path, "check-ignore", "-q", "--", target.path]).code == 0 else {
                log.append("SKIP alvo não ignorado pelo Git: \(target.path)")
                continue
            }
            guard let activeDirectories = activeWorkingDirectories() else {
                blocked += 1
                log.append("BLOCK inspeção de processos indisponível: \(target.path)")
                continue
            }
            if activeDirectories.contains(where: { CleanupPolicy.pathsOverlap($0, gitRoot.path) }) {
                blocked += 1
                log.append("BLOCK processo ativo: \(target.path)")
                continue
            }

            let statusBefore = run("/usr/bin/git", ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]).output
            guard !CleanupPolicy.isProtected(target.path, protectedPaths: protectedPaths),
                  CleanupPolicy.pathsOverlap(target.path, gitRoot.path) else {
                blocked += 1
                log.append("BLOCK limite protegido: \(target.path)")
                continue
            }

            do {
                try FileManager.default.removeItem(at: target)
            } catch {
                failed += 1
                log.append("ERROR remoção: \(target.path) \(error.localizedDescription)")
                continue
            }

            let statusAfter = run("/usr/bin/git", ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]).output
            guard statusBefore == statusAfter, !FileManager.default.fileExists(atPath: target.path) else {
                failed += 1
                log.append("ERROR verificação pós-limpeza: \(target.path)")
                continue
            }
            removed += 1
            log.append("REMOVED \(target.path) sizeKiB=\(sizeKiB)")
        }
        return (removed, blocked, failed)
    }

    private static func artifactCandidates() -> [URL] {
        let fileManager = FileManager.default
        var roots = ["Projects", "Projetos", "Developer", "Code"].map { home.appending(path: $0) }
        let excludedTopLevel = Set([
            "Applications", "Desktop", "Documents", "Downloads", "Library", "Movies", "Music",
            "Pictures", "Public", "Arquivos Públicos", "Arquivos Públicos",
        ])

        if let children = try? fileManager.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) {
            for child in children where !excludedTopLevel.contains(child.lastPathComponent) {
                let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
                if fileManager.fileExists(atPath: child.appending(path: "package.json").path)
                    || fileManager.fileExists(atPath: child.appending(path: ".git").path) {
                    roots.append(child)
                }
            }
        }

        var seen = Set<String>()
        return roots.flatMap(enumerateArtifacts).filter { seen.insert($0.path).inserted }
    }

    private static func enumerateArtifacts(in root: URL) -> [URL] {
        guard !CleanupPolicy.isProtected(root.path, protectedPaths: protectedPaths) else { return [] }
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let excludedNames = Set([".git", ".claude", ".codex", ".npm", ".npm-global", ".9router", ".vscode", ".Trash", "Library", "Arquivos Públicos", "Arquivos Públicos"])
        var results: [URL] = []

        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: Set(keys))
            guard values?.isDirectory == true else { continue }
            let name = url.lastPathComponent
            if values?.isSymbolicLink == true || excludedNames.contains(name) {
                enumerator.skipDescendants()
                continue
            }
            if name == "node_modules" || name == ".next" {
                results.append(url)
                enumerator.skipDescendants()
            }
        }
        return results
    }

    private static func activeWorkingDirectories() -> [String]? {
        let result = run("/usr/sbin/lsof", [
            "-a", "-u", NSUserName(), "-d", "cwd", "-Fn",
        ])
        guard result.code == 0 else { return nil }
        return result.output.split(separator: "\n").compactMap { line in
            line.first == "n" ? String(line.dropFirst()) : nil
        }
    }

    private static func gitRoot(for target: URL) -> URL? {
        let result = run("/usr/bin/git", ["-C", target.deletingLastPathComponent().path, "rev-parse", "--show-toplevel"])
        guard result.code == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path)
    }

    private static func run(_ executable: String, _ arguments: [String]) -> CommandResult {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return CommandResult(code: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        } catch {
            return CommandResult(code: -1, output: error.localizedDescription)
        }
    }
}

private struct CommandResult: Sendable {
    let code: Int32
    let output: String
}

private struct CleanupLog: Sendable {
    let url: URL

    func append(_ message: String) {
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        let stamp = ISO8601DateFormatter().string(from: Date())
        try? handle.write(contentsOf: Data("\(stamp) \(message)\n".utf8))
    }
}
