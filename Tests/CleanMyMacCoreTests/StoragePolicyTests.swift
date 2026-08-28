import Foundation
import Testing
@testable import CleanMyMacCore

@Test func thresholdsAndCooldown() {
    #expect(StoragePolicy.level(for: 0.89) == .normal)
    #expect(StoragePolicy.level(for: 0.90) == .warning)
    #expect(StoragePolicy.level(for: 0.95) == .critical)
    #expect(StoragePolicy.shouldResetWarning(for: 0.87))

    let now = Date(timeIntervalSince1970: 100_000)
    #expect(StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.95,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: nil,
        now: now
    ))
    #expect(!StoragePolicy.shouldRunAutomaticCleanup(
        usedFraction: 0.96,
        enabled: true,
        isCleaning: false,
        lastCleanupAt: now.addingTimeInterval(-60),
        now: now
    ))
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
}

@Test func cleanupPolicyKeepsArtifactsInsideTheirGitRoot() {
    #expect(CleanupPolicy.pathsOverlap("/Users/example/Projects/app/node_modules", "/Users/example/Projects/app"))
    #expect(!CleanupPolicy.pathsOverlap("/Users/example/Other/node_modules", "/Users/example/Projects/app"))
    #expect(CleanupPolicy.isProtected(
        "/Users/example/Documents/client/node_modules",
        protectedPaths: ["/Users/example/Documents"]
    ))
}
