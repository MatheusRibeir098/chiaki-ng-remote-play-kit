# 01 — O problema: por que o Remote Play "nunca conectava"

**Em uma frase:** três defeitos independentes, empilhados, faziam o chiaki-ng travar para sempre em *"Cancelling connection with console over PSN…"* — e cada um escondia o seguinte, então consertar só um deles não mudava nada visível.

Este documento é o estudo de caso real (14/set/2026, Arch Linux, PS5 Pro, notebook numa rede corporativa). Os outros docs detalham cada correção. Se você só quer resolver, vá para o [README](../README.md) e rode `make check`.

## O sintoma

Ao conectar no console pela internet (entrada "via PSN"), o app ficava indefinidamente nesta tela:

```
Cancelling connection with console over PSN ...
```

Nem cancelar funcionava. O processo não estava congelado — todas as threads em `poll` normal — mas a máquina de estados esperava um callback que nunca chegava. `SIGTERM` era ignorado; só `SIGKILL` encerrava. Reabrir e tentar de novo dava o mesmo resultado, sempre.

Na rede de casa (mesma rede do PS5) funcionava normalmente, porque aí o chiaki conecta direto no IP local e o caminho PSN nem é usado.

## As três causas, na ordem em que apareceram

### Causa 1 — Certificado: a Sony não envia a cadeia completa

Primeira linha de erro no log de sessão:

```
[E] websocket_thread_func: Connecting to push notification WebSocket
    wss://<redacted>-pushcl.np.communication.playstation.net/np/pushNotification
    failed with CURL error SSL peer certificate or SSH remote key was not OK
```

O servidor de *push* do PSN entrega **só o certificado folha**, sem a intermediária `COMODO RSA Domain Validation Secure Server CA`. Navegadores completam a cadeia sozinhos (via AIA); a libcurl não. Sem esse WebSocket, o holepunch nunca começa — e o cancelamento espera por ele para sempre. Esse é o travamento.

**Por que mascarava o resto:** enquanto o WebSocket falha, nada depois dele executa. Não há como saber que existem mais dois problemas.

→ Detalhes e correção: [02-certificado-psn.md](02-certificado-psn.md)

### Causa 2 — Binário velho: o pacote do AUR mente a versão

Com o certificado resolvido, a sessão avançou e caiu em outro lugar:

```
[I] >> Created offer msg for ctrl connection
[E] chiaki_holepunch_session_start: Failed to decode "customData1": '<redacted>' with error Unknown
[E] !! Failed to start session
```

O PS5 Pro devolve um campo `customData1` de **17 bytes**; o código antigo exige exatamente 16. Isso é a [issue #810](https://github.com/streetpea/chiaki-ng/issues/810) do chiaki-ng.

A parte confusa: o mantenedor fechou a issue dizendo *"That was already fixed a while ago try 1.10"* — e o pacote instalado dizia `chiaki-ng 1.10.0-2`. Mas o `PKGBUILD` do AUR fixa `_commit=3f8fd712…`, de **10/ago/2025**, 107 commits **antes** do fix (`254d37ae8`, 19/mar/2026). Ou seja: o número de versão é 1.10.0, o código é de 2025. O binário até se apresenta como `Chiaki Version 1.9.9` no log.

**Por que mascarava o resto:** a sessão morre antes de tentar qualquer conexão de mídia.

→ Detalhes e correção: [03-build.md](03-build.md)

### Causa 3 — Rede: servidores STUN bloqueados atrasam tudo até o console desistir

Com o binário certo, a conexão chegou até o vídeo — e falhou ali:

```
[I] >> Punched hole for data connection!
[I] Takion connecting (version 7)
[E] Takion recv failed: Conexão recusada
[E] Takion failed to receive init ack
[E] Senkusha connect timeout
[E] Senkusha Takion connect failed
```

O canal de **controle** conectava (o PIN era até pedido e aceito), mas o canal de **dados/vídeo** recebia "conexão recusada" instantaneamente. Parecia firewall corporativo bloqueando UDP — e era, mas de forma indireta.

O chiaki baixa em tempo de execução uma lista pública de servidores STUN (`pradt2/always-online-stun`). Na rede testada, os **7 primeiros da lista eram bloqueados**. Cada um gasta ~5s até o timeout:

```
[W] Failed to get external address from stun.smslisto.com:3478, retrying with another STUN server...
[W] Failed to get external address from stun.freevoipdeal.com:3478, retrying...
[W] Failed to get external address from stun.voipbuster.com:3478, retrying...
(…mais 4)
```

Resultado: a fase de dados demorava ~35s. O console não espera tanto — quando o pacote finalmente chegava, a porta já tinha sido fechada do lado dele, e o roteador de casa devolvia *port unreachable* ("conexão recusada").

Redirecionando esses 7 hostnames para um STUN que a rede não bloqueia (Cloudflare), a fase caiu para ~1s e o vídeo conectou.

→ Detalhes e correção: [04-rede-restrita.md](04-rede-restrita.md)

## Linha do tempo da descoberta (para você não repetir)

| Hora | O que parecia | O que era |
|---|---|---|
| 10:01 | App travado | Causa 1 (certificado) — travamento é sintoma, não causa |
| 10:49 | Certificado corrigido, "ainda falha" | O app precisa ser **reiniciado**: tenta o WebSocket uma vez, na abertura |
| 10:59 | `Failed to decode customData1` | Causa 2 — e a issue #810 dizia "já corrigido" |
| 11:05 | Pacote "1.10.0" instalado | Commit de 2025. Versão mentia. |
| 11:14 | PIN pedido e aceito, vídeo "recusado" | Causa 3 — parecia firewall, era atraso de STUN |
| 11:38 | Conectou | — |
| 11:43 | Conectou a partir do console em repouso | 1ª tentativa acorda o console; 2ª conecta (normal) |

Cerca de **1h40** de diagnóstico. Com este kit: `make check` diz quais das três causas existem na sua máquina/rede em ~30s.

## Tabela final: sintoma → causa → correção

| Linha no log | Causa | Correção |
|---|---|---|
| `SSL peer certificate or SSH remote key was not OK` | Intermediária COMODO ausente | `make install-ca` e **reiniciar o chiaki** |
| `Failed to decode "customData1"` | Binário anterior ao fix do PS5 Pro | `make build` |
| `Failed to get external address from stun.*` (vários) + `Takion recv failed: Conexão recusada` | STUN bloqueados na rede → console desiste | `make stun` |
| `Ctrl received Login message: PIN incorrect` | Passcode do perfil do PS5 errado | Ver [05](05-primeira-conexao.md) |
| `Timed out waiting for holepunch session start` logo após pôr em repouso | Console ainda acordando | Tentar de novo |

## Como saber se este é o seu caso

Abra o log mais recente em `~/.local/share/Chiaki/Chiaki/log/` e procure as linhas da tabela acima — ou rode `make doctor`, que faz isso por você e nomeia a causa.

## Como reverter

Cada correção tem sua própria seção de reversão. Para desfazer tudo: [99-reverter-tudo.md](99-reverter-tudo.md) ou `make revert`.
