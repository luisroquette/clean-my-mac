import AppKit
import CleanMyMacCore
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var monitor: StorageMonitor
    @State private var confirmingCleanup = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            storageCard

            Toggle("Limpeza automática", isOn: $monitor.automaticCleanupEnabled)
                .toggleStyle(.switch)
                .accessibilityHint("Executa a limpeza segura quando o armazenamento chega a 78 por cento")

            Toggle(
                "Abrir ao iniciar sessão",
                isOn: Binding(
                    get: { monitor.launchAtLoginEnabled },
                    set: { monitor.setLaunchAtLogin($0) }
                )
            )
            .toggleStyle(.switch)

            if monitor.launchAtLoginNeedsApproval {
                Label("Aguardando aprovação em Itens de Início", systemImage: "person.crop.circle.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Text(monitor.lastAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Divider()

            HStack(spacing: 8) {
                Button("Verificar agora") {
                    Task { await monitor.sampleNow() }
                }
                .disabled(monitor.isSampling || monitor.isCleaning)

                Button(monitor.isCleaning ? "Limpando…" : "Limpar agora") {
                    confirmingCleanup = true
                }
                .buttonStyle(.borderedProminent)
                .tint(statusColor)
                .disabled(monitor.isCleaning)

                Spacer()

                Menu {
                    Button("Abrir log") {
                        NSWorkspace.shared.open(monitor.logURL.deletingLastPathComponent())
                    }
                    Divider()
                    Button("Sair") { NSApplication.shared.terminate(nil) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("Mais opções")
            }
        }
        .padding(18)
        .frame(width: 380)
        .background(.ultraThinMaterial)
        .confirmationDialog(
            "Executar limpeza segura agora?",
            isPresented: $confirmingCleanup,
            titleVisibility: .visible
        ) {
            Button("Limpar caches e artefatos", role: .destructive) {
                monitor.cleanNow()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Somente caches e node_modules/.next ignorados pelo Git serão removidos. Projetos ativos, arquivos pessoais, credenciais e a Lixeira serão preservados.")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: monitor.menuBarSymbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 44, height: 44)
                .background(statusColor.opacity(0.13), in: RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 2) {
                Text("Clean My Mac")
                    .font(.headline)
                Text(statusTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if monitor.isCleaning {
                ProgressView().controlSize(.small)
            }
        }
    }

    private var storageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(monitor.snapshot.map { "\($0.usedPercent)%" } ?? "—")
                    .font(.system(size: 28, weight: .semibold, design: .rounded).monospacedDigit())
                Text("usado")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(freeSpace)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: monitor.snapshot?.usedFraction ?? 0)
                .tint(statusColor)
                .accessibilityLabel("Uso do armazenamento")
                .accessibilityValue(monitor.snapshot.map { "\($0.usedPercent) por cento" } ?? "indisponível")

            HStack {
                Label("Alerta em 75%", systemImage: "bell")
                Spacer()
                Label("Limpeza em 78%", systemImage: "sparkles")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
    }

    private var statusTitle: String {
        switch monitor.level {
        case .normal: "Armazenamento saudável"
        case .warning: "Armazenamento em atenção"
        case .critical: "Limpeza necessária"
        }
    }

    private var statusColor: Color {
        switch monitor.level {
        case .normal: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    private var freeSpace: String {
        guard let snapshot = monitor.snapshot else { return "Lendo…" }
        return "\(ByteCountFormatter.string(fromByteCount: Int64(snapshot.availableBytes), countStyle: .file)) livres"
    }
}
