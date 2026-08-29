import CleanMyMacCore
import Darwin
import Foundation

struct CleanupResult: Sendable {
    let destination: CleanupDestination
    let removedTargets: Int
    let blockedTargets: Int
    let failedTargets: Int
    let freedBytes: UInt64

    var summary: String {
        let freed = ByteCountFormatter.string(fromByteCount: Int64(freedBytes), countStyle: .file)
        let completed: String
        switch destination {
        case .trash:
            completed = "\(removedTargets) itens movidos para a Lixeira"
        case .deleteBatch:
            completed = "\(freed) liberados com segurança"
        case .externalBackup:
            completed = "\(freed) liberados após backup verificado"
        }
        if failedTargets > 0 {
            return "\(completed); \(failedTargets) falhas verificadas. Nova tentativa agendada."
        }
        if blockedTargets > 0 {
            return "\(completed); \(blockedTargets) projetos ativos preservados."
        }
        return "\(completed)."
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

    static func run(
        includeNativeCaches: Bool = true,
        destination: CleanupDestination = .deleteBatch,
        externalBackupPath: String? = nil
    ) async -> CleanupResult {
        await Task.detached(priority: .utility) {
            runSynchronously(
                includeNativeCaches: includeNativeCaches,
                destination: destination,
                externalBackupPath: externalBackupPath
            )
        }.value
    }

    static func prepareLog() {
        CleanupLog(url: logURL).append("MONITOR app iniciado")
    }

    static func record(_ message: String) {
        CleanupLog(url: logURL).append(message)
    }

    private static let scanFailureReasonLimit = 200

    static func scanFailureLogMessage(operation: String, path: String, result: CommandResult) -> String? {
        guard result.code != 0 else { return nil }
        return "ERROR \(operation): \(path) \(sanitizedScanFailureReason(result.output))"
    }

    /// Strips control characters (including NUL and newlines) so a scan failure never breaks
    /// the log into multiple lines or embeds unreadable bytes, and caps the reason to a bounded
    /// length so one failure can't dump an entire find/du result set into the log.
    private static func sanitizedScanFailureReason(_ raw: String) -> String {
        let cleaned = String(raw.unicodeScalars.map {
            CharacterSet.controlCharacters.contains($0) ? " " : Character($0)
        })
        let collapsed = cleaned.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        guard collapsed.count > scanFailureReasonLimit else { return collapsed }
        return "\(collapsed.prefix(scanFailureReasonLimit))…"
    }

    /// Parses the leading whitespace-separated field of `du -sk` output as kibibytes.
    /// Returns nil when the output doesn't start with a number, distinguishing a genuine
    /// parse failure (log-worthy) from a legitimately small/ineligible artifact.
    static func parseDuSizeKiB(_ output: String) -> Int? {
        guard let first = output.split(whereSeparator: { $0.isWhitespace }).first else { return nil }
        return Int(first)
    }

    private static func runSynchronously(
        includeNativeCaches: Bool,
        destination: CleanupDestination,
        externalBackupPath: String?
    ) -> CleanupResult {
        let before = (try? StorageReader.read().availableBytes) ?? 0
        var removedTargets = 0
        var blockedTargets = 0
        var failedTargets = 0
        let log = CleanupLog(url: logURL)
        log.append("START armazenamento seguro destino=\(destination.rawValue)")

        var disposal = DisposalSession(
            destination: destination,
            externalBackupPath: externalBackupPath
        )
        let artifactResult = cleanGeneratedArtifacts(log: log, disposal: &disposal)
        removedTargets += artifactResult.removed
        blockedTargets += artifactResult.blocked
        failedTargets += artifactResult.failed
        if !disposal.finalize(log: log) {
            failedTargets += 1
        }
        if includeNativeCaches, destination == .deleteBatch {
            cleanNativeCaches(log: log)
        } else if includeNativeCaches {
            log.append("CACHE limpeza nativa ignorada para respeitar o destino escolhido")
        } else {
            log.append("CACHE limpeza nativa adiada para priorizar o limite de 80%")
        }
        let after = (try? StorageReader.read().availableBytes) ?? before
        let freed = after > before ? after - before : 0
        log.append("END liberados=\(freed) removidos=\(removedTargets) bloqueados=\(blockedTargets) falhas=\(failedTargets)")
        return CleanupResult(
            destination: destination,
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
            let result = runCommand(executable, arguments, timeout: 120)
            log.append("CACHE \(executable) exit=\(result.code) \(result.output)")
        }
    }

    private static func cleanGeneratedArtifacts(
        log: CleanupLog,
        disposal: inout DisposalSession
    ) -> (removed: Int, blocked: Int, failed: Int) {
        var removed = 0
        var blocked = 0
        var failed = 0
        do {
            try disposal.validate()
        } catch {
            log.append("ERROR destino indisponível: \(error.localizedDescription)")
            return (0, 0, 1)
        }
        let scanStartedAt = Date()
        let candidates = artifactCandidates(log: log)
        let scanMilliseconds = Int(Date().timeIntervalSince(scanStartedAt) * 1_000)
        log.append("SCAN candidatos=\(candidates.count) duracaoMs=\(scanMilliseconds)")

        guard let activeDirectories = activeWorkingDirectories() else {
            log.append("BLOCK inspeção de processos indisponível")
            return (0, candidates.count, 0)
        }
        for target in candidates {
            guard let gitRoot = gitRoot(for: target) else {
                log.append("SKIP sem Git: \(target.path)")
                continue
            }
            guard runCommand("/usr/bin/git", ["-C", gitRoot.path, "check-ignore", "-q", "--", target.path]).code == 0 else {
                log.append("SKIP alvo não ignorado pelo Git: \(target.path)")
                continue
            }
            if CleanupPolicy.isProjectActive(gitRoot.path, activeDirectories: activeDirectories) {
                blocked += 1
                log.append("BLOCK processo ativo: \(target.path)")
                continue
            }
            guard !CleanupPolicy.isProtected(target.path, protectedPaths: protectedPaths),
                  CleanupPolicy.pathsOverlap(target.path, gitRoot.path) else {
                blocked += 1
                log.append("BLOCK limite protegido: \(target.path)")
                continue
            }

            let sizeResult = runCommand("/usr/bin/du", ["-sk", target.path])
            if let message = scanFailureLogMessage(operation: "medição de tamanho", path: target.path, result: sizeResult) {
                log.append(message)
            }
            let sizeKiB = sizeResult.code == 0 ? parseDuSizeKiB(sizeResult.output) : nil
            if sizeResult.code == 0, sizeKiB == nil {
                log.append("ERROR medição de tamanho: saída inesperada de du: \(target.path)")
            }
            guard let sizeKiB,
                  CleanupPolicy.isEligibleArtifact(
                      name: target.lastPathComponent,
                      sizeKiB: sizeKiB,
                      isSymbolicLink: false,
                      minimumKiB: minimumArtifactKiB
                  ) else { continue }

            guard let currentActiveDirectories = activeWorkingDirectories() else {
                blocked += 1
                log.append("BLOCK rechecagem de processos indisponível: \(target.path)")
                continue
            }
            if CleanupPolicy.isProjectActive(gitRoot.path, activeDirectories: currentActiveDirectories) {
                blocked += 1
                log.append("BLOCK processo iniciou durante a varredura: \(target.path)")
                continue
            }

            let statusBefore = runCommand(
                "/usr/bin/git",
                ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
            )
            guard statusBefore.code == 0 else {
                blocked += 1
                log.append("BLOCK Git indisponível antes da limpeza: \(target.path)")
                continue
            }

            let receipt: ArtifactReceipt
            do {
                receipt = try disposal.stage(
                    target,
                    expectedBytes: UInt64(sizeKiB) * 1_024
                )
            } catch {
                failed += 1
                log.append("ERROR destino: \(target.path) \(error.localizedDescription)")
                continue
            }

            let statusAfter = runCommand(
                "/usr/bin/git",
                ["-C", gitRoot.path, "status", "--porcelain=v1", "-z"]
            )
            guard CleanupPolicy.isVerifiedAfterCleanup(
                statusBefore: statusBefore.output,
                statusAfter: statusAfter.output,
                statusAfterExitCode: statusAfter.code,
                targetStillExists: FileManager.default.fileExists(atPath: target.path)
            ) else {
                do {
                    try disposal.restore(receipt)
                } catch {
                    disposal.preserveBatch()
                    log.append("ERROR restauração; lote preservado: \(target.path) \(error.localizedDescription)")
                }
                failed += 1
                log.append("ERROR verificação pós-limpeza: \(target.path)")
                continue
            }
            removed += 1
            log.append("REMOVED \(target.path) sizeKiB=\(sizeKiB)")
        }
        return (removed, blocked, failed)
    }

    private static func artifactCandidates(log: CleanupLog) -> [URL] {
        let fileManager = FileManager.default
        var roots = CleanupPolicy.artifactScanRoots(homePath: home.path)
            .map { URL(filePath: $0, directoryHint: .isDirectory) }
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
        return roots.flatMap { enumerateArtifacts(in: $0, log: log) }.filter { seen.insert($0.path).inserted }
    }

    private static func enumerateArtifacts(in root: URL, log: CleanupLog) -> [URL] {
        guard !CleanupPolicy.isProtected(root.path, protectedPaths: protectedPaths) else { return [] }
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }

        var arguments = [root.path, "-type", "d", "("]
        for (index, pattern) in CleanupPolicy.excludedDirectoryPatterns.enumerated() {
            if index > 0 { arguments.append("-o") }
            arguments += ["-name", pattern]
        }
        arguments += ["-o", "-path", "*/Warning/Default"]
        arguments += [
            ")", "-prune", "-o", "-type", "d", "(",
            "-name", "node_modules", "-o", "-name", ".next",
            ")", "-print0", "-prune",
        ]

        let result = runCommand("/usr/bin/find", arguments)
        if let message = scanFailureLogMessage(operation: "varredura de artefatos", path: root.path, result: result) {
            log.append(message)
        }
        guard result.code == 0 else { return [] }
        return result.output.split(separator: "\0").compactMap { rawPath in
            let url = URL(filePath: String(rawPath), directoryHint: .isDirectory)
            return CleanupPolicy.isProtected(url.path, protectedPaths: protectedPaths) ? nil : url
        }
    }

    private struct DisposalSession {
        let destination: CleanupDestination
        let externalBackupPath: String?
        private var batchRoot: URL?
        private var removalBatchRoot: URL?
        private var mustPreserveBatch = false
        private var successfulItems = 0

        init(destination: CleanupDestination, externalBackupPath: String?) {
            self.destination = destination
            self.externalBackupPath = externalBackupPath
        }

        func validate() throws {
            guard destination == .externalBackup else { return }
            guard let externalBackupPath,
                  CleanupDestinationPolicy.isExternalBackupPath(externalBackupPath),
                  FileManager.default.fileExists(atPath: externalBackupPath),
                  FileManager.default.isWritableFile(atPath: externalBackupPath) else {
                throw DisposalError.externalDriveUnavailable
            }
            let values = try URL(filePath: externalBackupPath).resourceValues(
                forKeys: [.volumeIsInternalKey, .volumeIsReadOnlyKey]
            )
            guard values.volumeIsInternal == false, values.volumeIsReadOnly != true else {
                throw DisposalError.externalDriveUnavailable
            }
        }

        mutating func stage(_ target: URL, expectedBytes: UInt64) throws -> ArtifactReceipt {
            let root = try ensureBatchRoot()
            let destinationURL = target.pathComponents.dropFirst().reduce(root) {
                $0.appending(path: $1, directoryHint: .inferFromPath)
            }
            try FileManager.default.createDirectory(
                at: destinationURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            switch destination {
            case .trash, .deleteBatch:
                try FileManager.default.moveItem(at: target, to: destinationURL)
                successfulItems += 1
                return .staged(original: target, stored: destinationURL)
            case .externalBackup:
                let values = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
                if let capacity = values.volumeAvailableCapacityForImportantUsage,
                   capacity < Int64(expectedBytes) {
                    throw DisposalError.insufficientExternalSpace
                }
                let removalRoot = try ensureRemovalBatchRoot()
                let stagedOriginal = target.pathComponents.dropFirst().reduce(removalRoot) {
                    $0.appending(path: $1, directoryHint: .inferFromPath)
                }
                do {
                    try BackupVerifier.copyVerifiedAndStageRemoval(
                        source: target,
                        backup: destinationURL,
                        removalStaging: stagedOriginal
                    )
                } catch {
                    if FileManager.default.fileExists(atPath: stagedOriginal.path)
                        || !FileManager.default.fileExists(atPath: target.path) {
                        mustPreserveBatch = true
                        throw DisposalError.originalUnavailable
                    }
                    throw error
                }
                successfulItems += 1
                return .backedUp(
                    original: target,
                    backup: destinationURL,
                    stagedOriginal: stagedOriginal
                )
            }
        }

        func restore(_ receipt: ArtifactReceipt) throws {
            try FileManager.default.createDirectory(
                at: receipt.original.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            switch receipt {
            case let .staged(original, stored):
                try FileManager.default.moveItem(at: stored, to: original)
            case let .backedUp(original, backup, stagedOriginal):
                try FileManager.default.moveItem(at: stagedOriginal, to: original)
                try BackupVerifier.verifyCopy(source: backup, destination: original)
            }
        }

        mutating func preserveBatch() {
            mustPreserveBatch = true
        }

        mutating func finalize(log: CleanupLog) -> Bool {
            guard let batchRoot else { return true }
            if mustPreserveBatch {
                log.append("ERROR lote mantido para recuperação: \(batchRoot.path)")
                if let removalBatchRoot {
                    log.append("ERROR original local preservado para recuperação: \(removalBatchRoot.path)")
                }
                return false
            }
            if successfulItems == 0 {
                try? FileManager.default.removeItem(at: batchRoot)
                if let removalBatchRoot {
                    try? FileManager.default.removeItem(at: removalBatchRoot)
                }
                guard !FileManager.default.fileExists(atPath: batchRoot.path),
                      removalBatchRoot.map({ !FileManager.default.fileExists(atPath: $0.path) }) ?? true else {
                    log.append("ERROR lote sem itens confirmados não pôde ser descartado")
                    return false
                }
                log.append("CLEAN lote sem itens confirmados descartado")
                return true
            }
            switch destination {
            case .trash:
                log.append("TRASH lote recuperável: \(batchRoot.path)")
                return true
            case .externalBackup:
                log.append("BACKUP lote verificado: \(batchRoot.path)")
                guard let removalBatchRoot else { return true }
                return deleteExactTrashBatch(removalBatchRoot, log: log)
            case .deleteBatch:
                return deleteExactTrashBatch(batchRoot, log: log)
            }
        }

        private func deleteExactTrashBatch(_ root: URL, log: CleanupLog) -> Bool {
            let escapedPath = root.path
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            let script = """
            with timeout of 600 seconds
                tell application "Finder" to delete POSIX file "\(escapedPath)"
            end timeout
            """
            let result = SafeCleaner.runCommand("/usr/bin/osascript", ["-e", script], timeout: 620)
            guard result.code == 0, !FileManager.default.fileExists(atPath: root.path) else {
                log.append("ERROR lote mantido para recuperação: \(root.path) \(result.output)")
                return false
            }
            log.append("DELETE lote exato concluído: \(root.path)")
            return true
        }

        private mutating func ensureBatchRoot() throws -> URL {
            if let batchRoot { return batchRoot }
            let batchName = "\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)"
            let root: URL
            switch destination {
            case .trash, .deleteBatch:
                root = SafeCleaner.home
                    .appending(path: ".Trash", directoryHint: .isDirectory)
                    .appending(path: "CleanMyMac-\(batchName)", directoryHint: .isDirectory)
            case .externalBackup:
                guard let externalBackupPath else { throw DisposalError.externalDriveUnavailable }
                root = URL(filePath: externalBackupPath, directoryHint: .isDirectory)
                    .appending(path: "Clean My Mac Backups", directoryHint: .isDirectory)
                    .appending(path: batchName, directoryHint: .isDirectory)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            batchRoot = root
            return root
        }

        private mutating func ensureRemovalBatchRoot() throws -> URL {
            if let removalBatchRoot { return removalBatchRoot }
            let root = SafeCleaner.home
                .appending(path: ".Trash", directoryHint: .isDirectory)
                .appending(
                    path: "CleanMyMac-BackupRemoval-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString)",
                    directoryHint: .isDirectory
                )
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            removalBatchRoot = root
            return root
        }
    }

    private enum ArtifactReceipt {
        case staged(original: URL, stored: URL)
        case backedUp(original: URL, backup: URL, stagedOriginal: URL)

        var original: URL {
            switch self {
            case let .staged(original, _), let .backedUp(original, _, _): original
            }
        }
    }

    private enum DisposalError: LocalizedError {
        case externalDriveUnavailable
        case insufficientExternalSpace
        case originalUnavailable

        var errorDescription: String? {
            switch self {
            case .externalDriveUnavailable:
                "O HD externo escolhido não está montado ou não permite gravação."
            case .insufficientExternalSpace:
                "O HD externo não tem espaço livre suficiente para verificar o backup."
            case .originalUnavailable:
                "O original não pôde ser confirmado nem restaurado; os lotes foram preservados."
            }
        }
    }

    private static func activeWorkingDirectories() -> [String]? {
        let result = runCommand("/usr/sbin/lsof", [
            "-a", "-u", NSUserName(), "-d", "cwd", "-Fn",
        ])
        guard result.code == 0 else { return nil }
        return result.output.split(separator: "\n").compactMap { line in
            line.first == "n" ? String(line.dropFirst()) : nil
        }
    }

    private static func gitRoot(for target: URL) -> URL? {
        let result = runCommand("/usr/bin/git", ["-C", target.deletingLastPathComponent().path, "rev-parse", "--show-toplevel"])
        guard result.code == 0 else { return nil }
        let path = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.isEmpty ? nil : URL(filePath: path)
    }

    static func runCommand(
        _ executable: String,
        _ arguments: [String],
        timeout: TimeInterval = 60
    ) -> CommandResult {
        let fileManager = FileManager.default
        let outputURL = fileManager.temporaryDirectory
            .appending(path: "CleanMyMac-command-\(UUID().uuidString).log")
        guard fileManager.createFile(atPath: outputURL.path, contents: nil),
              let outputHandle = try? FileHandle(forWritingTo: outputURL) else {
            return CommandResult(code: -1, output: "não foi possível criar a saída temporária")
        }
        defer {
            try? outputHandle.close()
            try? fileManager.removeItem(at: outputURL)
        }

        let process = Process()
        let terminated = DispatchSemaphore(value: 0)
        process.executableURL = URL(filePath: executable)
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = outputHandle
        process.terminationHandler = { _ in terminated.signal() }
        do {
            try process.run()
            let timedOut = terminated.wait(timeout: .now() + timeout) == .timedOut
            if timedOut {
                process.terminate()
                if terminated.wait(timeout: .now() + 5) == .timedOut {
                    kill(process.processIdentifier, SIGKILL)
                    _ = terminated.wait(timeout: .now() + 2)
                }
            } else {
                process.waitUntilExit()
            }
            try? outputHandle.synchronize()
            let data = (try? Data(contentsOf: outputURL)) ?? Data()
            let output = String(decoding: data, as: UTF8.self)
            return timedOut
                ? CommandResult(code: 124, output: "tempo limite de \(Int(timeout)) segundos excedido")
                : CommandResult(code: process.terminationStatus, output: output)
        } catch {
            return CommandResult(code: -1, output: error.localizedDescription)
        }
    }
}

struct CommandResult: Sendable {
    let code: Int32
    let output: String
}

private struct CleanupLog: Sendable {
    let url: URL
    private static let lock = NSLock()

    func append(_ message: String) {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           CleanupLogPolicy.shouldRotate(size: UInt64(size)) {
            let previous = url.deletingLastPathComponent().appending(path: "clean-my-mac.previous.log")
            try? fileManager.removeItem(at: previous)
            try? fileManager.moveItem(at: url, to: previous)
        }
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
