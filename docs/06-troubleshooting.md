# 06 — Troubleshooting: do log para a correção

**Em uma frase:** o log de sessão do chiaki-ng diz exatamente qual das causas está ativa; esta tabela traduz cada linha em uma ação — e `make doctor` faz a leitura por você.

## Onde está o log

```
~/.local/share/Chiaki/Chiaki/log/chiaki_session_<data>_<hora>.log
```
Um arquivo por abertura do app. O mais recente:
```sh
ls -t ~/.local/share/Chiaki/Chiaki/log/*.log | head -1
```
O log redige IPs, IDs e tokens como `<redacted-...>`. Ainda assim, **ele contém o PIN que você digitou** (`Set login pin "…"`) — não cole logs inteiros em lugar público sem apagar essas linhas.

## Ligar o log detalhado

Só quando precisar — gera milhares de linhas por minuto de stream. Com o chiaki **fechado**, em `~/.config/Chiaki/Chiaki.conf`, seção `[settings]`:
```ini
log_verbose=true
```
Mostra os candidatos de holepunch, o estado da sessão (`Holepunch session state: … ✅CONSOLE_JOINED …`) e cada pacote Takion. Desligue depois.

## Filtrar o ruído

O libplacebo imprime ~100 linhas de formatos Vulkan a cada redraw. Para ler o que importa:
```sh
grep -vE 'libplacebo|VK_FORMAT|VK_COLOR|swapchain|Heartbeat|seq num|data ack|P frame' <log> | tail -40
```

## Tabela: linha → significado → ação

| Linha no log | O que significa | Ação |
|---|---|---|
| `Connecting to push notification WebSocket ... failed with CURL error SSL peer certificate or SSH remote key was not OK` | Falta a intermediária COMODO no trust store. Nada depois disso roda. | `make install-ca`, depois **feche e abra o chiaki** ([02](02-certificado-psn.md)) |
| `Canceling establishing connection over PSN` como última linha, app parado em "Cancelling connection…" | Consequência da linha acima: o cancelamento espera um WebSocket que nunca abriu. | Matar o processo (abaixo), corrigir o certificado |
| `Failed to decode "customData1": '…' with error Unknown` + `!! Failed to start session` | Binário anterior ao fix do PS5 Pro (17 bytes). | `make build` ([03](03-build.md)) |
| `decode_customdata1: customData1 contains 1 extra byte(s); ignoring extras` | **Bom sinal** — binário com o fix funcionando. | Nada |
| Várias `Failed to get external address from stun.*:3478, retrying with another STUN server...` | Sua rede bloqueia esses STUN; cada um custa ~5 s. | `make stun` ([04](04-rede-restrita.md)) |
| `Failed to resolve STUN server 'stun.freevoipdeal.com'` | Host morto na lista pública. Mesmo tratamento. | `make stun` |
| `Punched hole for data connection!` → `Takion recv failed: Conexão recusada` → `Senkusha Takion connect failed` | Vídeo recusado: console desistiu (atraso de STUN) ou NAT simétrico. | Se há STUN falhando acima: `make stun`. Senão: tentar de novo; se persistir, hotspot |
| `Rudp raw failed to send packet: Conexão recusada` (repetido) + `Ctrl has failed since session started, exiting` | Mesma causa; o controle caiu junto. | Idem |
| `Ctrl received Login message: PIN incorrect` | Passcode do perfil do PS5 errado. | Conferir no console ([05](05-primeira-conexao.md)). Não insistir às cegas |
| `wait_for_notification: Timed out waiting for holepunch session messages` + `Timed out waiting for holepunch session start notifications` | Console não entrou na sessão em 30 s. Quase sempre: estava em repouso e acabou de acordar. | Tentar de novo. Se 3× seguidas: revisar ajustes de repouso no PS5 |
| `Holepunch session state: … ✅DATA_SENT ]` sem `✅CONSOLE_JOINED` depois | Mesma coisa, visto pelo verbose. | Idem |
| `UPnP discovery timed out after 7000 ms, skipping` / `Failed to find UPnP-capable devices` | Rede sem UPnP (normal fora de casa). Custa 7 s, não impede nada. | Ignorar |
| `IPV6 NOT supported by your PlayStation console. Skipping IPV6 connection` | Informativo. | Ignorar |
| `Simulate User Activity Error: … org.freedesktop.ScreenSaver` | Seu compositor não expõe essa interface DBus. Só afeta inibição de tela. | Ignorar |
| `StreamConnection successfully received streaminfo` | **Conectou.** | Jogar |

## `make doctor`

`scripts/90-doctor.sh` aplica esta tabela ao log mais recente (ou ao arquivo passado como argumento) e imprime a causa mais provável com o `make …` correspondente. Use antes de pedir ajuda: a saída dele já é o relatório.

## Chiaki travado em "Cancelling connection…"

Ele ignora `SIGTERM`. Sem derrubar sua sessão gráfica:
```sh
pkill -x chiaki; sleep 3; pkill -KILL -x chiaki
```
Depois corrija a causa (quase sempre o certificado) antes de reabrir.

## Confirmar cada correção sem abrir o chiaki

```sh
# certificado: 0 = ok, 20 = falta emissor
curl -sS -o /dev/null -w 'ssl=%{ssl_verify_result}\n' https://44-232-96-0-pushcl.np.communication.playstation.net/
# binário: 1 = tem o fix
strings /usr/bin/chiaki | grep -c 'contains %zu extra byte'
# STUN: bloco presente?
grep -c 'chiaki-ng-remote-play-kit STUN' /etc/hosts
```
`make check` roda os três e mais o teste de NAT.

## Como saber se este é o seu caso

Se você chegou aqui, é. Rode `make doctor`.

## Como reverter

Cada linha da tabela aponta para o doc da correção, que tem sua reversão. Tudo de uma vez: [99-reverter-tudo.md](99-reverter-tudo.md).
