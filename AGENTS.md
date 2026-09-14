# AGENTS.md — instruções para agentes de IA

Você foi acionado para instalar ou consertar o Remote Play do PS5 no Arch Linux usando este kit. Leia tudo antes de rodar qualquer coisa.

## Contexto em 5 linhas

1. O chiaki-ng oficial funciona; o que quebra são três coisas ao redor dele: certificado ausente na cadeia da Sony, pacote `chiaki-ng` do AUR fixado em código antigo (sem o fix do `customData1` de 17 bytes do PS5 Pro), e servidores STUN bloqueados em redes corporativas.
2. Este kit corrige as três com scripts idempotentes e reversíveis. Ele **não** altera código do chiaki-ng.
3. Tudo já foi validado de ponta a ponta em Arch Linux, PS5 Pro, notebook em rede corporativa. Se algo divergir, o log do chiaki é a fonte da verdade, não a sua hipótese.
4. Os scripts vivem em `scripts/`, os alvos em `Makefile`, a explicação em `docs/`.
5. Segredos (token PSN, chave de registro, PIN) vivem em `~/.config/Chiaki/Chiaki.conf` e **nunca** entram no repositório nem no chat.

## Ordem obrigatória de execução

Siga exatamente. Não pule o passo 1 nem antecipe o 4.

```
make check                # 1. só lê. Leia o VEREDITO no final antes de continuar.
make install-ca           # 2. só se o check apontou "certificado faltando"
make build                # 3. só se o check apontou "binário antigo/ausente"
make config               # 4. template de config; não sobrescreve segredos existentes
make stun                 # 5. SOMENTE se o check apontou "STUN bloqueado"
chiaki                    # 6. abrir; o humano faz login PSN, registro e digita o PIN na GUI
make doctor               # 7. em QUALQUER falha, rode isto ANTES de formular hipóteses
```

`make install` equivale a 1→4. Após cada passo, confirme o resultado com o comando de verificação indicado na saída do próprio script; não assuma sucesso pelo código de saída apenas.

Antes de `make install-ca` e `make stun`, rode primeiro com `--dry-run` e mostre ao humano o que será alterado:

```
scripts/10-install-ca-intermediate.sh --dry-run
scripts/30-stun-redirect.sh --dry-run
```

## Regras duras

- **Nunca desabilite ufw, firewalld, iptables ou nftables.** O firewall local foi investigado e descartado como causa; desabilitá-lo não resolve nada e expõe a máquina. Se você acha que o firewall é o problema, rode `make doctor` e mostre a evidência.
- **Nunca peça o PIN do console nem a senha da PSN em texto.** O humano digita na interface gráfica do chiaki. Se ele te oferecer, recuse e explique.
- **Nunca commite `Chiaki.conf`**, nem cópias ou trechos dele. Está no `.gitignore` por isso. Nunca cole o conteúdo desse arquivo no chat.
- **Nunca instale o pacote `chiaki-ng` do AUR.** Ele declara versão 1.10.0 mas compila um commit de agosto/2025, anterior ao fix. Use `make build` (PKGBUILD pinado em `packaging/arch/`) ou o pré-compilado da Release.
- **Não use `CURL_CA_BUNDLE`, `SSL_CERT_FILE` nem `SSL_CERT_DIR`** para contornar o certificado. A libcurl do Arch fixa o caminho do bundle em compilação e ignora essas variáveis — foi testado diretamente contra a libcurl. O único caminho é o trust store do sistema (`make install-ca`).
- **Não tente mais de 3 PINs.** Cada erro conta como tentativa de login no PS5 e pode bloquear o perfil temporariamente. Depois do terceiro erro, peça ao humano para conferir no console.
- **Após o PS5 sair do repouso, tente conectar de novo antes de diagnosticar.** A primeira tentativa só acorda o console (timeout de 30 s, volta à tela inicial). Isso é comportamento normal, não falha.
- **Não edite `Chiaki.conf` com o chiaki aberto.** Ele reescreve o arquivo ao fechar e desfaz sua edição.
- **Não mexa em `/etc/hosts` fora do bloco do kit** (`# chiaki-ng: STUN bloqueados` … `# fim chiaki-ng STUN`). O script `30` gerencia só esse bloco.

## Como interpretar o log

Log mais recente: `ls -t ~/.local/share/Chiaki/Chiaki/log/*.log | head -1`. Filtre o ruído com `grep -vE 'libplacebo|VK_FORMAT|VK_COLOR'`. Assinaturas exatas e o que fazer:

| Linha no log | Causa | Ação |
|---|---|---|
| `websocket_thread_func: ... failed with CURL error SSL peer certificate or SSH remote key was not OK` | Intermediária COMODO ausente no trust store | `make install-ca`, depois **reinicie o chiaki** (ele só tenta o WebSocket uma vez, na inicialização) |
| `chiaki_holepunch_session_start: Failed to decode "customData1"` … `with error Unknown` | Binário sem o fix dos 17 bytes | `make build` (ou `--prebuilt`) |
| Vários `Failed to receive STUN response` seguidos + depois `Takion recv failed: Conexão recusada` / `Senkusha Takion connect failed` | Servidores STUN bloqueados atrasam a oferta em ~30 s e o console desiste | `make stun` |
| `wait_for_notification: Timed out waiting for holepunch session start notifications` + `!! Failed to start session` | Console em repouso ainda acordando, ou "ligar pela rede" desativado no PS5 | Tentar de novo; se persistir, conferir *Economia de energia* no console |
| `Ctrl received Login message: PIN incorrect` | PIN do perfil errado | Humano confere no PS5; máximo 3 tentativas |
| `Canceling establishing connection over PSN` e nada depois por minutos | Processo travado no cancelamento (versão antiga) | `pkill -KILL -x chiaki`; depois `make doctor` para achar a causa raiz |
| `decode_customdata1: customData1 contains 1 extra byte(s); ignoring extras` | **Fix funcionando** (informativo) | Nada |
| `StreamConnection successfully received streaminfo` | **Conectou** | Nada |

`make doctor` aplica exatamente esta tabela e imprime o veredito; use `--json` se precisar processar a saída. `--log <arquivo>` analisa um log específico.

## Quando parar e chamar o humano

Pare e explique, em vez de insistir, quando:

- `make check` reportar distro não suportada (não é Arch nem derivado).
- O PIN falhou 3 vezes.
- O doctor disser "Console não respondeu" em **3 tentativas seguidas** com intervalo de 30 s — provavelmente a configuração de repouso do PS5 está desativada e só quem está perto do console resolve.
- Qualquer passo pedir uma ação no console físico (registro inicial, conferir configurações).
- Você estiver prestes a fazer algo fora do escopo dos scripts do kit (editar arquivos de sistema por conta própria, instalar outros pacotes, mudar rede). Não faça; pergunte.
- Você não conseguir explicar a falha com uma linha da tabela acima. Não invente causa; mostre o log filtrado e peça ajuda.

## Relatório final ao usuário

Ao terminar (com sucesso ou não), entregue exatamente nesta forma, em português, sem jargão desnecessário:

```
## Resultado
Conectou / Não conectou (motivo em uma frase)

## O que foi feito
- [passo] → [comando] → [como verifiquei]
  (um por linha, só os executados; diga explicitamente o que foi pulado e por quê)

## O que mudou no sistema
- Certificado: instalado em /etc/ca-certificates/trust-source/anchors/ (ou "não alterado")
- Pacote: chiaki-ng-git <versão> (ou "não alterado")
- /etc/hosts: N servidores STUN redirecionados (ou "não alterado")
- Config: <o que o template aplicou> (ou "não alterado")

## Como desfazer
make revert  (e `sudo pacman -R chiaki-ng-git` para o pacote)

## Pendências para o humano
- (ex.: registrar o console em casa; conferir modo de repouso no PS5; nada)
```

Não inclua tokens, PIN, MAC, IP do console ou trechos de `Chiaki.conf` no relatório.
