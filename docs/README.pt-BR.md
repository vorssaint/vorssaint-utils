# Vorssaint

> O conjunto de utilitários gratuito e open source que substitui vários apps pagos do Mac.

*Read in [English](../README.md).*

Se o Vorssaint te ajuda, uma ⭐ rápida significa muito. Ele é 100% gratuito, então dar uma estrela é, por enquanto, a única forma de apoiar o projeto, e ainda ajuda mais gente a encontrá-lo.

Um app pequeno na barra de menus que faz o trabalho para o qual você instalaria
(e pagaria) vários utilitários separados: manter o Mac acordado, ver o que está
deixando ele lento, ajustar o volume por app, alternar janelas, e resolver
algumas chatices do dia a dia.

**Grátis. Open source. Local.** Sem conta, sem assinatura, sem telemetria, sem
IA. Nada sai do seu Mac, exceto uma verificação de atualização que você pode
desligar. É nativo (SwiftUI + AppKit), não é Electron, então fica pequeno e rápido.

<p align="center">
  <img src="screenshot.png" alt="O painel do Vorssaint na barra de menus: manter acordado, mixer de volume por app e monitor do sistema ao vivo com temperaturas, uso de CPU e GPU e pressão de memória" width="420">
</p>

## O que ele faz

Cada recurso é opcional e tem a sua própria página nos Ajustes.

### 🌡️ Veja o que está deixando o Mac lento
Temperaturas de CPU, GPU e bateria, uso de CPU/GPU ao vivo e pressão de memória,
direto na barra de menus. Toque em qualquer leitura para ver quais apps estão por trás.

### 🎚️ Ajuste o volume por app
Abaixe o Safari sem mexer no Spotify nem no Zoom. O mixer por app que o macOS
nunca trouxe, com um ponto ao vivo no que está tocando. (macOS 14.4 ou mais recente.)

### 🪟 Vá para qualquer janela na hora
Substitui o ⌘Tab por uma grade com miniaturas reais das janelas, incluindo várias
janelas do mesmo app, e um toque rápido que volta para a última janela usada.

### ⚡ Mantenha o Mac acordado sob demanda
Para um download, um build ou uma apresentação: com tempo definido ou até você
desligar, mesmo com a tampa fechada. A proteção de bateria desliga quando a carga fica baixa.

### 🖱️ Corrija a direção da rolagem do mouse
Inverte a roda do mouse sem mexer na rolagem natural do trackpad.

### ✂️ Mova arquivos no Finder com ⌘X / ⌘V
Recorte arquivos e pastas e cole em outra pasta: o "mover" que falta no Finder.
Campos de texto seguem com os atalhos normais.

### ❌ Feche a última janela e o app encerra
Quando a última janela de um app fecha, ele é encerrado e libera a memória, com
uma lista de exceções para os apps que você prefere manter abertos.

### 🗑️ Remova um app e tudo que ele deixou para trás
Solte um app nos Ajustes para encontrar caches, preferências, logs e outros
resíduos, revise a lista e mande tudo para a Lixeira.

### 📥 Uma área para carregar arquivos
Uma bandeja flutuante, chamada perto do cursor, que guarda arquivos, imagens,
textos e links para você arrastar entre apps, janelas e desktops.

## Por que é feito assim

- **Grátis e open source**, sob uma licença não comercial. Sem níveis pagos.
- **Local por padrão.** Sem conta, sem login, sem telemetria. A única chamada de
  rede verifica se há nova versão no GitHub, e dá para desligar.
- **Nativo e leve.** SwiftUI + AppKit puro, sem dependências externas, um app
  pequeno no lugar de vários.
- **Opcional por princípio.** Cada recurso vem desligado até você ativar, pede
  permissão só quando precisa e funciona de forma degradada sem ela.

## Instalação

### Download (recomendado)
Baixe o DMG mais recente em [**Releases**](https://github.com/vorssaint/vorssaint-utils/releases),
abra e arraste o **Vorssaint** para **Aplicativos**.

O Vorssaint é assinado com um Developer ID e notarizado pela Apple, então abre
normalmente, sem aviso de segurança. A assinatura estável também mantém as
permissões concedidas entre as atualizações.

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
| **Acessibilidade** | Inversor de rolagem, teclado do alternador, recortar e colar, encerrar ao fechar | Esses recursos ficam desligados |
| **Gravação de Tela** | Títulos e miniaturas no alternador | Alternador mostra só ícones |
| **Notificações** | Avisos de fim de sessão e proteção de bateria | Operação silenciosa |
| **Acesso Total ao Disco** (opcional) | Varredura mais completa do desinstalador | Varre só os locais acessíveis |
| **Administrador** (uma vez, opcional) | Tampa fechada sem senha | Pede senha a cada uso |

Recortar e colar e o desinstalador também pedem o consentimento de Automação na
primeira vez que falam com o Finder. A área temporária não precisa de nenhuma
permissão.

A primeira abertura traz um onboarding curto e guiado (idioma, permissões e uma
página opcional por recurso). Reveja quando quiser em **Ajustes › Sobre**.

## Desinstalação

```sh
./Tools/uninstall.sh   # de um clone, ou baixe do repositório
```
Encerra o app, remove o item de início, redefine as permissões de Acessibilidade
e Gravação de Tela, apaga o app, as preferências e o estado salvo, e remove a
regra `sudoers` opcional de tampa fechada, sem deixar nada para trás. Ou arraste
o app para a Lixeira e rode `tccutil reset All com.vorssaint.utils` para limpar
as permissões.

## Licença

[PolyForm Noncommercial License 1.0.0](../LICENSE), © 2026 Vorssaint. Livre para
usar, modificar e compartilhar para qualquer fim **não comercial**, com
atribuição. Uso comercial não é permitido.
