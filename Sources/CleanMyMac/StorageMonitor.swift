import CleanMyMacCore
import Foundation
import ServiceManagement
import UserNotifications

@MainActor
final class StorageMonitor: ObservableObject {
    @Published private(set) var snapshot: StorageSnapshot?
    @Published private(set) var lastUpdatedAt: Date?
    @Published private(set) var lastAction = "Iniciando monitoramento…"
    @Published private(set) var isSampling = false
    @Published private(set) var isCleaning = false
    @Published private(set) var launchAtLoginEnabled = false
    @Published private(set) var launchAtLoginNeedsApproval = false

    @Published var automaticCleanupEnabled: Bool {
        didSet { defaults.set(automaticCleanupEnabled, forKey: Keys.automaticCleanup) }
    }

    private let defaults: UserDefaults
    private var monitoringTask: Task<Void, Never>?
    private var warningLatched: Bool
    private var lastCleanupAt: Date?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        automaticCleanupEnabled = defaults.object(forKey: Keys.automaticCleanup) as? Bool ?? true
        warningLatched = defaults.bool(forKey: Keys.warningLatched)
        lastCleanupAt = defaults.object(forKey: Keys.lastCleanupAt) as? Date

        Task { [weak self] in
            await self?.start()
        }
    }

    deinit {
        monitoringTask?.cancel()
    }

    var level: StorageLevel {
        StoragePolicy.level(for: snapshot?.usedFraction ?? 0)
    }

    var menuBarSymbol: String {
        switch level {
        case .normal: "externaldrive.fill"
        case .warning: "externaldrive.badge.exclamationmark"
        case .critical: "exclamationmark.triangle.fill"
        }
    }

    var menuBarTitle: String {
        snapshot.map { "\($0.usedPercent)%" } ?? "—"
    }

    var logURL: URL { SafeCleaner.logURL }

    func start() async {
        guard monitoringTask == nil else { return }
        SafeCleaner.prepareLog()
        configureLoginItemOnFirstLaunch()
        await sampleNow()
        Task { await requestNotificationAuthorization() }

        monitoringTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                await self?.sampleNow()
            }
        }
    }

    func sampleNow(allowAutomation: Bool = true) async {
        guard !isSampling else { return }
        isSampling = true
        defer { isSampling = false }

        do {
            let sample = try await Task.detached(priority: .utility) {
                try StorageReader.read()
            }.value
            snapshot = sample
            lastUpdatedAt = Date()
            lastAction = "Disco verificado: \(sample.usedPercent)% em uso."
            await react(to: sample, allowAutomation: allowAutomation)
        } catch {
            lastAction = "Falha ao ler o disco: \(error.localizedDescription)"
        }
    }

    func cleanNow(isAutomatic: Bool = false) {
        guard !isCleaning else { return }
        isCleaning = true
        lastAction = isAutomatic ? "Limpeza automática iniciada…" : "Limpeza segura iniciada…"

        Task {
            let result = await SafeCleaner.run()
            let now = Date()
            lastCleanupAt = now
            defaults.set(now, forKey: Keys.lastCleanupAt)
            isCleaning = false
            lastAction = result.summary
            await sampleNow(allowAutomation: false)

            let percent = snapshot?.usedPercent ?? 0
            if percent >= Int(StoragePolicy.hardLimit * 100) {
                await notify(
                    title: "SSD acima do limite seguro",
                    body: "A limpeza segura terminou, mas o disco continua em \(percent)%. Nova tentativa em 15 minutos.",
                    critical: true
                )
            } else {
                await notify(
                    title: "Clean My Mac concluiu a limpeza",
                    body: result.summary,
                    critical: false
                )
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard BundleContext.isBundledApp else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refreshLoginItemState()
        } catch {
            lastAction = "Falha no início automático: \(error.localizedDescription)"
        }
    }

    private func react(to sample: StorageSnapshot, allowAutomation: Bool) async {
        if StoragePolicy.shouldResetWarning(for: sample.usedFraction) {
            warningLatched = false
            defaults.set(false, forKey: Keys.warningLatched)
        }

        if allowAutomation, StoragePolicy.shouldRunAutomaticCleanup(
            usedFraction: sample.usedFraction,
            enabled: automaticCleanupEnabled,
            isCleaning: isCleaning,
            lastCleanupAt: lastCleanupAt
        ) {
            await notify(
                title: "Clean My Mac iniciou a limpeza",
                body: "O armazenamento chegou a \(sample.usedPercent)%.",
                critical: true
            )
            cleanNow(isAutomatic: true)
            return
        }

        if sample.usedFraction >= StoragePolicy.warningThreshold, !warningLatched {
            warningLatched = true
            defaults.set(true, forKey: Keys.warningLatched)
            await notify(
                title: "Armazenamento quase cheio",
                body: "O disco está em \(sample.usedPercent)%. A limpeza automática começa em 78% para proteger o teto de 80%.",
                critical: sample.usedFraction >= StoragePolicy.cleanupThreshold
            )
        }
    }

    private func requestNotificationAuthorization() async {
        guard BundleContext.isBundledApp else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    private func notify(title: String, body: String, critical: Bool) async {
        guard BundleContext.isBundledApp else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if critical { content.sound = .default }
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "storage-\(Int(Date().timeIntervalSince1970))",
                content: content,
                trigger: nil
            )
        )
    }

    private func configureLoginItemOnFirstLaunch() {
        guard BundleContext.isBundledApp else { return }
        if !defaults.bool(forKey: Keys.didConfigureLoginItem) {
            do {
                try SMAppService.mainApp.register()
                defaults.set(true, forKey: Keys.didConfigureLoginItem)
            } catch {
                lastAction = "Abra Itens de Início para autorizar o monitor."
            }
        }
        refreshLoginItemState()
    }

    private func refreshLoginItemState() {
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLoginEnabled = true
            launchAtLoginNeedsApproval = false
        case .requiresApproval:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = true
        default:
            launchAtLoginEnabled = false
            launchAtLoginNeedsApproval = false
        }
    }

    private enum Keys {
        static let automaticCleanup = "automaticCleanupEnabled"
        static let warningLatched = "warningLatched"
        static let lastCleanupAt = "lastCleanupAt"
        static let didConfigureLoginItem = "didConfigureLoginItem"
    }
}

enum BundleContext {
    static var isBundledApp: Bool {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }
}
