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
