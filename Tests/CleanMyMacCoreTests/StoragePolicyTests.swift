import Foundation
import Testing
@testable import CleanMyMacCore

@Test func thresholdsAndCooldown() {
    #expect(StoragePolicy.level(for: 0.74) == .normal)
    #expect(StoragePolicy.level(for: 0.745) == .warning)
    #expect(StoragePolicy.level(for: 0.75) == .warning)
    #expect(StoragePolicy.level(for: 0.775) == .critical)
    #expect(StoragePolicy.level(for: 0.78) == .critical)
    #expect(StoragePolicy.hardLimit == 0.80)
    #expect(StoragePolicy.emergencyThreshold == 0.95)
    #expect(StoragePolicy.shouldResetWarning(for: 0.72))
    #expect(StoragePolicy.isAtOrAboveHardLimit(0.796))
    #expect(!StoragePolicy.isAtOrAboveHardLimit(0.794))

    let now = Date(timeIntervalSince1970: 100_000)
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.78,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: nil,
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.79,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-60),
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.79,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-61),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.774,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: nil,
        now: now
    ))
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.80,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-15),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.80,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-14),
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.97,
        enabled: false,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-121),
        now: now
    ))
    #expect(StoragePolicy.monitoringInterval(for: 0.74) == 30)
    #expect(StoragePolicy.monitoringInterval(for: 0.75) == 5)
}

@Test func storageSnapshotNeverReportsNegativeUsage() {
    let snapshot = StorageSnapshot(totalBytes: 100, availableBytes: 120)
    #expect(snapshot.availableBytes == 100)
    #expect(snapshot.usedBytes == 0)
    #expect(snapshot.usedPercent == 0)
}

@Test func cleanupPolicyProtectsUnicodePathsAndRejectsUnsafeArtifacts() {
    let protected = ["/Users/example/Arquivos Públicos"]
    let decomposed = "/Users/example/Arquivos Públicos/Mac/Warning/Default"
    #expect(CleanupPolicy.isProtected(decomposed, protectedPaths: protected))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/Projects/client/Warning/Default/node_modules",
        protectedPaths: []
    ))
    #expect(!CleanupPolicy.isProtected(
        "/Users/example/Projects/client/Warning/Preview/node_modules",
        protectedPaths: []
    ))
    #expect(CleanupPolicy.pathsOverlap("/project", "/project/worktree"))
    #expect(CleanupPolicy.isEligibleArtifact(
        name: "node_modules",
        sizeKiB: 102_400,
        isSymbolicLink: false,
        minimumKiB: 102_400
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: "Downloads",
        sizeKiB: 1_000_000,
        isSymbolicLink: false,
        minimumKiB: 102_400
    ))
    #expect(!CleanupPolicy.isEligibleArtifact(
        name: ".next",
        sizeKiB: 200_000,
        isSymbolicLink: true,
        minimumKiB: 102_400
    ))
    #expect(CleanupPolicy.shouldExcludeDirectory(named: ".claude"))
    #expect(CleanupPolicy.shouldExcludeDirectory(named: "claude-501"))
    #expect(!CleanupPolicy.shouldExcludeDirectory(named: "cfgauss-claude-site"))
    #expect(CleanupPolicy.excludedDirectoryPatterns.contains(".claude"))
    #expect(CleanupPolicy.excludedDirectoryPatterns.contains("claude-*"))
    #expect(CleanupPolicy.isProjectActive(
        "/project",
        activeDirectories: ["/project/app"]
    ))
    #expect(!CleanupPolicy.isProjectActive(
        "/project",
        activeDirectories: ["/other/app"]
    ))
}

@Test func cleanupPolicyKeepsArtifactsInsideTheirGitRoot() {
    let roots = CleanupPolicy.artifactScanRoots(homePath: "/Users/example")
    #expect(roots.contains("/Users/example/Projects"))
    #expect(roots.contains("/private/tmp"))
    #expect(CleanupPolicy.pathsOverlap("/Users/example/Projects/app/node_modules", "/Users/example/Projects/app"))
    #expect(!CleanupPolicy.pathsOverlap("/Users/example/Other/node_modules", "/Users/example/Projects/app"))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/Documents/client/node_modules",
        protectedPaths: ["/Users/example/Documents"]
    ))
}

@Test func cleanupDestinationRequiresExternalVolume() {
    #expect(CleanupDestinationPolicy.isExternalBackupPath("/Volumes/ESPACO/Backups"))
    #expect(!CleanupDestinationPolicy.isExternalBackupPath("/Users/example/Backups"))
    #expect(!CleanupDestinationPolicy.isExternalBackupPath("/Volumes"))
}

@Test func backupVerifierRejectsChangedCopies() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let destination = root.appending(path: "destination")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
    try Data("conteúdo verificado".utf8).write(to: source.appending(path: "nested/file.txt"))
    try fileManager.createSymbolicLink(
        atPath: source.appending(path: "link.txt").path,
        withDestinationPath: "nested/file.txt"
    )
    try fileManager.copyItem(at: source, to: destination)
    try BackupVerifier.verifyCopy(source: source, destination: destination)

    try Data("conteúdo alterado".utf8).write(to: destination.appending(path: "nested/file.txt"))
    #expect(throws: BackupVerificationError.self) {
        try BackupVerifier.verifyCopy(source: source, destination: destination)
    }
}

@Test func verifiedBackupStagesOriginalBeforeDeletion() throws {
    let fileManager = FileManager.default
    let root = fileManager.temporaryDirectory.appending(path: UUID().uuidString)
    let source = root.appending(path: "source")
    let backup = root.appending(path: "external/backup")
    let removalStaging = root.appending(path: "trash/source")
    defer { try? fileManager.removeItem(at: root) }

    try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
    try Data("backup seguro".utf8).write(to: source.appending(path: "artifact.txt"))

    try BackupVerifier.copyVerifiedAndStageRemoval(
        source: source,
        backup: backup,
        removalStaging: removalStaging
    )

    #expect(!fileManager.fileExists(atPath: source.path))
    #expect(fileManager.fileExists(atPath: backup.path))
    #expect(fileManager.fileExists(atPath: removalStaging.path))
    try BackupVerifier.verifyCopy(source: backup, destination: removalStaging)
}
