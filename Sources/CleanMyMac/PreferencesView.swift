import CleanMyMacCore
import SwiftUI

struct PreferencesView: View {
    @ObservedObject var monitor: StorageMonitor

    var body: some View {
        Form {
            Section("Destino dos arquivos") {
                Picker(
                    "Depois da verificação segura",
                    selection: Binding(
                        get: { monitor.cleanupDestination },
                        set: { monitor.setCleanupDestination($0) }
                    )
                ) {
                    Text("Mover para a Lixeira").tag(CleanupDestination.trash)
                    Text("Lixeira + apagar o lote do app").tag(CleanupDestination.deleteBatch)
                    Text("Backup em HD externo + apagar do Mac").tag(CleanupDestination.externalBackup)
                }
                .pickerStyle(.radioGroup)

                Label(destinationDescription, systemImage: destinationIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if monitor.cleanupDestination == .externalBackup {
                Section("HD externo") {
                    LabeledContent("Pasta") {
                        Text(monitor.externalBackupPath ?? "Nenhuma selecionada")
                            .foregroundStyle(monitor.externalBackupPath == nil ? .orange : .secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Button("Escolher pasta…") {
                        monitor.chooseExternalBackupFolder()
                    }
                }
            }

            Section("Proteções permanentes") {
                Text("Somente .next e node_modules ignorados pelo Git, inativos e acima de 100 MB entram no lote. Arquivos pessoais, credenciais, projetos ativos e itens antigos da Lixeira permanecem intocados.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 540, height: monitor.cleanupDestination == .externalBackup ? 420 : 350)
        .navigationTitle("Clean My Mac")
    }

    private var destinationDescription: String {
        switch monitor.cleanupDestination {
        case .trash:
            "Recuperável. O espaço só volta depois que você esvaziar a Lixeira."
        case .deleteBatch:
            "Apaga somente o lote criado pelo app e preserva tudo que já estava na Lixeira."
        case .externalBackup:
            "Copia, compara cada arquivo por SHA-256 e só então remove o original do Mac."
        }
    }

    private var destinationIcon: String {
        switch monitor.cleanupDestination {
        case .trash: "trash"
        case .deleteBatch: "trash.slash"
        case .externalBackup: "externaldrive.badge.checkmark"
        }
    }
}
