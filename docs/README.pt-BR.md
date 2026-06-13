# Vorssaint Utils

> Uma central de utilidades premium e nativa para macOS — vivendo discretamente na barra de menus.

*Read in [English](../README.md).*

O Vorssaint Utils mantém o Mac acordado sob demanda, mostra as leituras do
sistema que realmente importam, dá ao mouse a rolagem estilo Windows sem mexer
no trackpad e substitui o ⌘Tab por um alternador de janelas com miniaturas
reais. 100% nativo (SwiftUI + AppKit), bilíngue (pt-BR / en-US), sem Electron,
sem analytics, sem chamadas de rede.

## Recursos

### ⚡ Manter acordado
- Liga/desliga pelo painel, pelo menu de clique direito ou pelo atalho global **⌃⌥⌘K**
- Sessões de 15 min a 8 h, ou indefinidas — com extensões de +15/+30/+60 min
- Mantenha a tela ligada, ou deixe-a apagar com o sistema acordado
- **Tampa fechada**: MacBook ativo mesmo fechado (`pmset disablesleep`,
  revertido automaticamente ao fim da sessão, ao sair do app e após quedas)
- **Sem senha (opcional)**: regra `sudoers` restrita a `pmset disablesleep 0/1`,
  validada com `visudo -c`, removível a qualquer momento
- **Proteção de bateria**: a sessão desliga abaixo de um limite de carga
- Contagem regressiva na barra de menus e notificações de fim de sessão

### 🌡️ Monitor do sistema
- **Temperaturas** de CPU, GPU e bateria — a leitura mais relevante de cada
  componente, direto do SMC
- **Uso de hardware**: % de CPU e % de GPU
- **Pressão de memória** com indicador semáforo
  (verde = normal, amarelo = atenção, vermelho = crítico) e memória em uso/total

### 🖱️ Rolagem estilo Windows
- Inverte **apenas a roda do mouse** — o trackpad continua com a rolagem natural
- Vale na hora, sem reiniciar, sem extensão de kernel

### 🪟 Alternador de janelas
- Substitui o **⌘Tab** por uma grade com cada janela em miniatura ao vivo —
  não apenas ícones
- **Abas são tratadas como apps**: cada aba do Safari/Chrome/Edge/Brave/Vivaldi
  é uma entrada própria, e o ⌘Tab alterna entre duas abas do mesmo navegador
  como faria entre dois apps (ordem real de uso recente, no nível da aba)
- Instantâneo: um toque rápido troca sem mostrar UI; a janela vem à frente na hora
- Segure ⌘ e toque Tab para navegar; Shift/← volta; solte para trocar; **Q**
  fecha o app selecionado; Esc cancela — fluido, animado, compatível com Mission
  Control e Spaces
- Sem a Gravação de Tela, degrada graciosamente para ícones

### 🎚️ Mixer de volume por app
- Ajuste o volume de cada app individualmente — algo que o macOS não oferece
  (process taps do CoreAudio, macOS 14.4+; nada é gravado)
- Todo app com conexão de áudio aparece, com indicador ao vivo para os que estão
  tocando; volumes persistem por app, e 100% = áudio intocado

### ✂️ Recortar e colar no Finder
- Pressione **⌘X** para recortar a seleção do Finder e **⌘V** para movê-la para
  a pasta que você está vendo — o "mover" que quem vem do Windows espera
- Funciona com vários arquivos e pastas; um HUD flutuante mostra o que está
  guardado e confirma o movimento. Em campos de texto, ⌘X e ⌘V seguem normais

### ❌ Encerrar ao fechar a última janela
- Quando a última janela de um app fecha, o app é encerrado — uma forma limpa de
  liberar memória, como no Windows
- Apps que rodam sem janela nunca são tocados, e uma lista de exceções mantém
  aberto qualquer app que você escolher

### 🗑️ Desinstalação completa de apps
- Arraste um app (ou escolha um) para encontrar caches, preferências, logs,
  contêineres e outros resíduos que ele deixa, com o tamanho de cada um
- Revise a lista e mova os selecionados para a Lixeira (reversível, nunca uma
  exclusão definitiva) e veja o espaço recuperado

### 📥 Área temporária
- Um espaço flutuante para juntar arquivos, imagens, textos e links e arrastá-los
  depois para qualquer app, janela ou desktop
- Chame-a perto do cursor com **⌃⌥⌘D** ou sacudindo o mouse durante o arraste —
  sem precisar de nenhuma permissão

> Os quatro utilitários acima são opcionais. Ative cada um no onboarding ou em
> **Ajustes › Recursos**, onde cada um tem sua própria página.

## Instalação

### Download (recomendado)
Baixe o DMG mais recente em [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
abra e arraste o **Vorssaint Utils** para **Aplicativos**.

> As releases são assinadas com um certificado próprio estável (sem o
> certificado pago da Apple), então as permissões concedidas sobrevivem às
> atualizações — mas o Gatekeeper ainda alerta na primeira abertura. Clique
> direito no app → **Abrir**, ou remova a quarentena:
> `xattr -d com.apple.quarantine "/Applications/Vorssaint Utils.app"`

### Compilar do código
```sh
git clone https://github.com/vorssaint/vorssaint-utils.git
cd vorssaint-utils
./build.sh            # compila, gera o ícone e monta o bundle assinado
./build.sh --install  # idem + instala em /Aplicativos e abre
```

### Requisitos
- macOS 14 (Sonoma) ou mais recente
- Apple Silicon
- Xcode Command Line Tools (para compilar)

## Permissões

Tudo é opcional — os recursos degradam graciosamente e o onboarding guia cada
concessão:

| Permissão | Usada por | Sem ela |
|---|---|---|
| **Acessibilidade** | Inversor de rolagem, teclado do alternador, recortar e colar, encerrar ao fechar | Esses recursos ficam desligados |
| **Gravação de Tela** | Títulos e miniaturas no alternador | Alternador mostra só ícones |
| **Notificações** | Avisos de fim de sessão e proteção de bateria | Operação silenciosa |
| **Acesso Total ao Disco** (opcional) | Varredura mais completa do desinstalador | Varre só os locais acessíveis |
| **Administrador** (uma vez, opcional) | Tampa fechada sem senha | Pede senha a cada uso |

Recortar/colar e as abas do alternador também pedem ao macOS o consentimento de
Automação na primeira vez que falam com o Finder ou um navegador. A área
temporária não precisa de nenhuma permissão.

A primeira abertura traz um onboarding guiado (idioma, permissões, tour do
monitor e uma página opcional por recurso). Quem atualiza de uma versão anterior
vê uma breve apresentação das novidades, uma única vez. Revise quando quiser em
**Ajustes › Sobre › Rever introdução**.

## Licença

[PolyForm Noncommercial License 1.0.0](../LICENSE) — © 2026 Vorssaint.
Livre para usar, modificar e compartilhar para qualquer fim **não comercial**,
com atribuição. Uso comercial não é permitido.
