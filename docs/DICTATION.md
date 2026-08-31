# Ditado

O Ditado é uma funcionalidade opcional do Vorssaint. A gravação é feita pelo
microfone escolhido e enviada somente quando o usuário encerra a sessão.

## Configuração

1. Abra **Ajustes → Ditado** e ative a funcionalidade.
2. Salve a chave do OpenAI ou Groq. As chaves ficam exclusivamente no Keychain.
3. Escolha idioma, modelo, microfone e atalho.
4. Em **Saída**, selecione **Transcrição crua** ou **Aprimorada**.

O modo aprimorado faz uma segunda solicitação textual ao mesmo provedor para
pontuação, correções evidentes e parágrafos. Se essa solicitação falhar, o texto
cru é inserido sem perda.

## Histórico e recuperação

O histórico é local e opcional. Quando o áudio é salvo, os arquivos ficam em
armazenamento privado com permissões do usuário. A tela de histórico permite
reproduzir em 1× ou 2×, apagar áudio separadamente e retranscrever uma gravação
com outro provedor/modelo. Uma nova tentativa nunca substitui o registro
original.

Também é possível importar um arquivo de áudio pelo Finder. O arquivo de origem
não é alterado; uma cópia privada pode ser guardada conforme a preferência de
salvamento de áudio.

## Privacidade

O áudio temporário é removido após a sessão quando o histórico não está ativo.
Nenhuma chave, áudio ou transcrição é gravada em logs ou backups de preferências.
O silenciamento de microfones de outros aplicativos durante reuniões permanece
deliberadamente fora desta versão.
