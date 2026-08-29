<p align="center">
  <img src="docs/img/app-icon.png" width="92" height="92" alt="Ícone do Clean My Mac">
</p>

<h1 align="center">Clean My Mac</h1>

<p align="center">
  <strong>Proteção autônoma de SSD para quem constrói com IA.</strong><br>
  Feito para o rastro técnico deixado por Codex, Claude Code e agentes de programação.
</p>

<p align="center">
  <a href="https://luisroquette.github.io/clean-my-mac/"><img src="https://img.shields.io/badge/BAIXAR-PARA%20MAC-F28C38?style=for-the-badge&logo=apple&logoColor=white" alt="Baixar Clean My Mac"></a>
  <a href="https://github.com/luisroquette/clean-my-mac/releases/tag/v1.1.3"><img src="https://img.shields.io/badge/VERSÃO-1.1.3-201C19?style=for-the-badge" alt="Versão 1.1.3"></a>
  <a href="https://github.com/luisroquette/clean-my-mac/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/luisroquette/clean-my-mac/ci.yml?branch=main&style=for-the-badge&label=CI" alt="Status do CI"></a>
</p>

<p align="center">
  <a href="https://luisroquette.github.io/clean-my-mac/"><img src="docs/img/og-card.png" alt="Clean My Mac protegendo o SSD de resíduos gerados por agentes de IA"></a>
</p>

## Sua IA termina a tarefa. Os gigabytes ficam.

Agentes trabalham em paralelo, criam worktrees, instalam dependências e repetem
builds. Depois da entrega, `node_modules`, `.next` e caches de ferramentas
continuam ocupando o SSD. O problema costuma aparecer tarde: a próxima build
falha, uma atualização para ou o macOS fica sem espaço de trabalho.

Clean My Mac monitora o volume de dados a cada 30 segundos e acelera para 5
segundos sob pressão, sem interromper o fluxo:

| 75% | 78% | 80% | 95% |
|:---:|:---:|:---:|:---:|
| **Alerta** | **Limpeza autônoma** | **Limite protegido** | **Pressão crítica** |
| Um aviso claro | Lista segura | Retry a cada 15 s | Proteções continuam ativas |

<p align="center">
  <img src="docs/img/readme-storage-control.png" alt="Modelo de decisão do Clean My Mac em 95% de uso do SSD">
</p>

## Uma categoria feita para fluxos com IA

CCleaner e utilitários genéricos fazem manutenção ampla do sistema. Clean My Mac
entende projetos de software: Git, worktrees, processos ativos, builds e caches
regeneráveis. O foco não é “limpar o Mac”; é impedir que agentes de código
consumam silenciosamente todo o SSD.

- **Autônomo:** inicia com a sessão e verifica o disco a cada 5 segundos acima de 75%.
- **Um clique:** `Limpar agora` executa a mesma política segura sob demanda.
- **Local:** nenhum dado, caminho ou evento sai do computador.
- **Auditável:** código, regras e log de cada execução são públicos ou locais.

## Como a decisão funciona

```mermaid
flowchart LR
    A[Monitor local\n30 s normal / 5 s sob pressão] --> B{Uso do SSD}
    B -->|abaixo de 75%| C[Observar]
    B -->|75%| D[Alertar]
    B -->|78% ou mais| E[Mapear artefatos]
    E --> F{Git ignorado,\nregenerável e inativo?}
    F -->|não| G[Preservar e registrar]
    F -->|sim| H[Remover e verificar]
    B -->|80% ou mais| I[Retry automático\na cada 15 segundos]
    I --> E
```

O percentual usado pela política é o mesmo número arredondado mostrado na
interface. Se o aplicativo exibe **80%**, o retry de proteção já está ativo.

## Contrato de segurança

| Pode remover | Nunca remove |
|---|---|
| Caches de npm, uv, Bun, Deno e Homebrew | Documentos, Mesa, Downloads e mídia pessoal |
| `node_modules` e `.next` com 100 MB ou mais | Fontes rastreadas ou conteúdo não ignorado pelo Git |
| Artefatos ignorados dentro de um repositório Git | Projetos usados por qualquer processo do utilizador |
| Somente após verificar Git e processos novamente | Lixeira, Docker, credenciais e discos externos |

A inspeção de processos falha de forma fechada: se o macOS não permitir
confirmar que um projeto está inativo, o alvo é preservado. O Git é comparado
antes e depois da remoção. Falhas e recriações entram no resultado da execução.

> O teto de 80% é **best-effort**. Se não existir espaço regenerável suficiente,
> o aplicativo alerta e preserva dados pessoais e projetos ativos. Ele não
> encerra agentes nem amplia sozinho a fronteira de exclusão.

## Destino da limpeza

Abra **Mais opções → Preferências** e escolha:

| Destino | Comportamento |
|---|---|
| **Mover para a Lixeira** | Mantém o lote recuperável; o espaço só retorna quando a Lixeira for esvaziada |
| **Lixeira + apagar o lote do app** | Apaga somente o novo lote do Clean My Mac; itens antigos da Lixeira ficam intocados |
| **Backup em HD externo + apagar do Mac** | Copia cada artefato, compara estrutura, tamanho e SHA-256, depois remove o original |

O backup externo aceita somente uma pasta gravável em um volume não interno. Se
o disco for desconectado, estiver cheio ou a cópia divergir, o original é
preservado e a execução falha de forma fechada.

## O que mudou na v1.2.0

- Preferências com Lixeira, exclusão do lote exato ou backup externo verificado.
- Backup externo preserva o original até a validação SHA-256 terminar.
- Varredura nativa encontra `.next` e `node_modules` sem atravessar caches internos.
- Retry reduzido para 15 segundos assim que o SSD alcança 80%.
- Monitoramento acelerado para 5 segundos a partir de 75%.
- Projetos ativos são descartados antes da medição lenta de tamanho.
- Temporários `claude-*` continuam permanentemente excluídos da limpeza.
- A barra do macOS mostra somente o percentual atual, sem ícone redundante.

## Instalação

1. Abra a [página oficial de download](https://luisroquette.github.io/clean-my-mac/#download).
2. Preencha nome, WhatsApp e e-mail para liberar o ZIP gratuito.
3. Mova **Clean My Mac.app** para `Aplicativos`.
4. Na primeira execução, rode:

```bash
xattr -dr com.apple.quarantine "/Applications/Clean My Mac.app"
open "/Applications/Clean My Mac.app"
```

O build atual requer **macOS 14+**, processador **Apple silicon** e usa assinatura
ad-hoc. Ainda não há notarização Apple.

## Uso

1. Procure o ícone de disco na barra superior do macOS, perto do Wi-Fi e relógio.
2. Mantenha **Limpeza automática** ativada.
3. Mantenha **Abrir ao iniciar sessão** ativado.
4. Use **Verificar agora** ou **Limpar agora** para uma execução imediata.

O log fica em:

```text
~/Library/Logs/CleanMyMac/clean-my-mac.log
```

[Assistir à demonstração real de 12 segundos](docs/video/clean-my-mac-demo.mp4)

## Arquitetura pequena e nativa

| Componente | Responsabilidade |
|---|---|
| `StorageMonitor` | Amostragem, notificações, login e orquestração |
| `StoragePolicy` | Limites, cooldown normal e retry emergencial |
| `SafeCleaner` | Candidatos, processos, Git, remoção e auditoria |
| `MenuBarView` | Interface SwiftUI na barra do macOS |

Swift 6, SwiftUI, AppKit, ServiceManagement e UserNotifications. Nenhuma
dependência de runtime, Electron, conta ou serviço de nuvem.

## Compilar e verificar

```bash
git clone https://github.com/luisroquette/clean-my-mac.git
cd clean-my-mac
./Scripts/preflight.sh
open "dist/Clean My Mac.app"
```

O preflight canônico executa validação do `Info.plist`, testes do modelo web,
E2E desktop/mobile, testes Swift, build de produção, verificação da versão
pública e assinatura do aplicativo.

## Escopo de projetos

A busca de artefatos cobre `~/Projects`, `~/Projetos`, `~/Developer`, `~/Code` e
pastas diretas da home que contenham `.git` ou `package.json`. Pastas ocultas,
áreas pessoais do macOS e caminhos protegidos são excluídos antes da varredura.

## Privacidade

Amostras de armazenamento, preferências e logs permanecem no Mac. O aplicativo
não contém cliente de rede, analytics, telemetria, conta ou backend remoto.

## Limitações conhecidas

- O teto de 80% depende da existência de artefatos seguros e inativos.
- O modo Lixeira não devolve espaço ao SSD até o usuário esvaziá-la.
- Projetos fora das raízes documentadas não são varridos.
- Caches só são limpos quando a respectiva ferramenta está instalada.
- O build distribuído é exclusivo para Apple silicon e ainda não é notarizado.
- A interface atual está em português do Brasil.

## Projeto aberto

[MIT](LICENSE) © 2026 [Luis Roquette](https://github.com/luisroquette).

Clean My Mac é um software independente. Não possui afiliação, patrocínio ou
endosso da MacPaw. “CleanMyMac” é marca de seu respectivo proprietário.
