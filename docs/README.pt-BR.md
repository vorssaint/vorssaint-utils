# Vorssaint

> O conjunto de utilitários gratuito e open source que substitui vários apps pagos do Mac.

<p align="center"><strong><a href="https://vorssaint.com">vorssaint.com</a></strong></p>

*Read in [English](../README.md).*

<p align="center">🇺🇸 🇧🇷 🇪🇸 🇩🇪 🇫🇷 🇮🇹 🇯🇵 🇨🇳</p>
<p align="center"><sub>A interface fala 8 idiomas, troque quando quiser nos Ajustes.</sub></p>

Se o Vorssaint te ajuda, uma ⭐ rápida significa muito e ainda ajuda mais gente a encontrar o projeto. Ele é, e sempre será, 100% gratuito e sem assinatura; o apoio da comunidade é o que mantém tudo vivo, então se quiser ajudar você também pode [me pagar um café](https://buymeacoffee.com/vorssaint) ☕.

Um app pequeno na barra de menus que faz o trabalho para o qual você instalaria
(e pagaria) vários utilitários separados: manter o Mac acordado, ver o que está
deixando ele lento, ajustar o volume por app, alternar janelas, carregar arquivos
entre apps, remover sobras e resolver algumas chatices do dia a dia.

**Grátis. Open source. Local-first.** Sem conta, sem assinatura, sem telemetria
do Vorssaint. Os recursos principais rodam no seu Mac; rede só entra em recursos
visíveis como atualização, teste de velocidade e ações do Homebrew que você
inicia. É feito com frameworks nativos do macOS, então fica pequeno e rápido.

**Instale com o [Homebrew](https://brew.sh):**

```sh
brew install --cask vorssaint/tap/vorssaint
```

Já tem o Vorssaint instalado? Adote a sua cópia no Homebrew sem reinstalar: `brew install --cask --adopt vorssaint/tap/vorssaint`. Você também pode [baixar o .dmg](https://github.com/vorssaint/vorssaint-utils/releases).

## O que ele faz

Os recursos podem ser ajustados pelos Ajustes ou direto pelo painel.

<table>
  <tr>
    <td width="50%" valign="top">
      <strong>⚡ Mantenha acordado, até com a tampa fechada</strong><br>
      <sub>Use um timer ou mantenha ativo até desligar. O modo tampa fechada é opcional e escopado.</sub><br><br>
      <img src="assets/readme/keep-awake-lid-closed.png" alt="Controles de manter acordado e tampa fechada" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>🌡️ Monitor do sistema com gráficos</strong><br>
      <sub>Acompanhe CPU, GPU, memória, temperaturas, bateria e uptime num painel compacto.</sub><br><br>
      <img src="assets/readme/system-monitor-graph.png" alt="Monitor do sistema com gráficos ao vivo" width="330">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>🌐 Velocidade e totais de rede</strong><br>
      <sub>Veja upload/download ao vivo, totais da sessão e um teste de velocidade embutido.</sub><br><br>
      <img src="assets/readme/network-section.png" alt="Seção de rede do monitor" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>🔋 Energia e bateria</strong><br>
      <sub>Veja consumo do sistema, entrada do adaptador, fluxo da bateria, saúde e ciclos.</sub><br><br>
      <img src="assets/readme/power-section.png" alt="Seção de energia e bateria" width="330">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>🎚️ Mixer de volume por app</strong><br>
      <sub>Abaixe ou aumente um app sem mexer no volume do resto do Mac.</sub><br><br>
      <img src="assets/readme/volume-mixer.png" alt="Mixer de volume por app" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>🪟 Alternador de janelas</strong><br>
      <sub>Substitui o ⌘Tab por miniaturas reais, incluindo várias janelas do mesmo app.</sub><br><br>
      <img src="assets/readme/window-switcher.gif" alt="Alternador de janelas com miniaturas reais" width="330">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>📥 Shelf para arquivos temporários</strong><br>
      <sub>Guarde arquivos, imagens, textos e links perto do cursor para arrastar depois.</sub><br><br>
      <img src="assets/readme/shelf-demonstration.gif" alt="Shelf guardando itens arrastados" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>🧭 Painel compacto por seções</strong><br>
      <sub>Alterne entre lista e seções, com Utilidades sempre por perto.</sub><br><br>
      <img src="assets/readme/utilities-section.png" alt="Seção de utilidades no painel compacto" width="330">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>✂️ Recorte e cole arquivos no Finder</strong><br>
      <sub>Use ⌘X e ⌘V para mover arquivos selecionados sem quebrar atalhos de texto.</sub><br><br>
      <img src="assets/readme/cut-and-paste.gif" alt="Recortar e colar arquivos no Finder" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>❌ Encerre apps ao fechar a última janela</strong><br>
      <sub>Feche a última janela e o app encerra, com exceções por app.</sub><br><br>
      <img src="assets/readme/quit-on-close.gif" alt="App encerrando ao fechar a última janela" width="330">
    </td>
  </tr>
  <tr>
    <td width="50%" valign="top">
      <strong>🗑️ Remova sobras de apps</strong><br>
      <sub>Solte um app nos Ajustes, revise caches, preferências e logs, e mande tudo para a Lixeira.</sub><br><br>
      <img src="assets/readme/uninstall-demo.gif" alt="Desinstalador encontrando sobras de apps" width="330">
    </td>
    <td width="50%" valign="top">
      <strong>🧼 Limpe o teclado com segurança</strong><br>
      <sub>O Modo de limpeza bloqueia o teclado e desbloqueia pelo overlay ou por uma sequência de tecla.</sub><br><br>
      <img src="assets/readme/utilities-section.png" alt="Modo de limpeza dentro de Utilidades" width="330">
    </td>
  </tr>
</table>

### Também incluído

- **🖱️ Corrija a direção da rolagem do mouse**: inverte a roda do mouse sem
  mexer na rolagem natural do trackpad.
- **🧪 Fan Control beta**: entrada de teste disponível, com controles manuais
  desativados até que os modelos de Mac sejam validados com segurança.

## Por que é feito assim

- **Grátis e open source**, sob GPL-3.0-or-later. Sem níveis pagos.
- **Local por padrão.** Sem conta, sem login, sem backend do Vorssaint e sem
  telemetria do Vorssaint. Rede só entra em recursos visíveis: atualização,
  teste de velocidade e busca, popularidade ou instalação pelo Homebrew.
- **Nativo e leve.** SwiftUI + AppKit puro, sem dependências externas, um app
  pequeno no lugar de vários.
- **Opcional por princípio.** Os recursos podem ser ajustados ou desativados,
  pedem permissão só quando precisam e funcionam de forma degradada sem ela.

## Instalação

### Homebrew (recomendado)
```sh
brew install --cask vorssaint/tap/vorssaint
```
Já tem o Vorssaint instalado e não quer reinstalar? Adote a sua cópia no
Homebrew:
```sh
brew install --cask --adopt vorssaint/tap/vorssaint
```
Depois disso, as atualizações chegam por `brew upgrade --cask vorssaint`.

### Download
Baixe o DMG mais recente em [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
abra e arraste o **Vorssaint** para **Aplicativos**.

O Vorssaint é assinado com um Developer ID e notarizado pela Apple, então abre
normalmente, sem aviso de segurança. A assinatura estável também mantém as
permissões concedidas entre as atualizações.

### Builds oficiais e forks
Builds oficiais do Vorssaint são distribuídos apenas pelo mantenedor do projeto.
Forks não oficiais devem usar outro nome, ícone, bundle identifier e identidade
de assinatura. A GPL cobre apenas o código-fonte e não concede permissão para
usar o nome Vorssaint, logo, ícone, identidade de bundle, trade dress ou
branding oficial. Veja [TRADEMARKS.md](../TRADEMARKS.md).

### Compilar do código
```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compila, gera o ícone e monta o bundle assinado
./build.sh --install  # idem, depois instala em /Aplicativos e abre
```

### Requisitos
- macOS 14 (Sonoma) ou mais recente
- Apple Silicon
- Xcode Command Line Tools (para compilar)

## Permissões

Tudo é opcional: os recursos funcionam de forma degradada e o onboarding guia
cada concessão.

| Permissão | Usada por | Sem ela |
|---|---|---|
| **Acessibilidade** | Inversor de rolagem, alternador, Dock Preview, recortar e colar, encerrar ao fechar | Esses recursos ficam desligados |
| **Gravação de Tela** | Títulos e miniaturas no alternador e no Dock Preview | Pré-visualizações ficam limitadas ou indisponíveis |
| **Gravação de Áudio do Sistema** | Volume por app e roteamento de saída no mixer | Apps continuam no áudio normal do sistema |
| **Notificações** | Avisos de fim de sessão e proteção de bateria | Operação silenciosa |
| **Acesso Total ao Disco** (opcional) | Varredura mais completa do desinstalador | Varre só os locais acessíveis |
| **Administrador** (uma vez, opcional) | Tampa fechada sem senha | Pede senha a cada uso |

Recortar e colar, o desinstalador e a abertura do Terminal pelo Homebrew também
podem pedir Automação na primeira vez que falam com Finder ou Terminal. A área
temporária não precisa de nenhuma permissão.

A primeira abertura traz um onboarding curto e guiado (idioma, permissões e uma
página opcional por recurso). Reveja quando quiser em **Ajustes › Sobre**.

## Desinstalação

```sh
./Tools/uninstall.sh   # de um clone, ou baixe do repositório
```
Encerra o app, remove o item de início, redefine as permissões de privacidade,
apaga o app, as preferências e o estado salvo, e remove a
regra `sudoers` opcional de tampa fechada, sem deixar nada para trás. Ou arraste
o app para a Lixeira e rode `tccutil reset All com.vorssaint.utils` para limpar
as permissões.

## Licença

O código-fonte é licenciado sob [GPL-3.0-or-later](../LICENSE), copyright
© 2026 Vorssaint. A licença cobre apenas o código-fonte. O branding do
Vorssaint é tratado separadamente em [TRADEMARKS.md](../TRADEMARKS.md).
