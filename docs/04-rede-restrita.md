# 04 — Rede restrita: quando o controle conecta e o vídeo é "recusado"

**Em uma frase:** em redes que bloqueiam UDP para destinos incomuns (empresa, universidade, hotel), os primeiros servidores STUN da lista que o chiaki baixa não respondem, cada um custa 5 segundos, o console desiste de esperar e o canal de vídeo volta "conexão recusada" — o kit redireciona só os servidores bloqueados para um que funciona.

Script: `scripts/30-stun-redirect.sh` · Atalho: `make stun` · **Opcional**: só se `make check` apontar STUN bloqueado.

## Dois canais, dois destinos

O Remote Play via PSN abre **duas** conexões UDP diretas com o console, uma de cada vez:

1. **Controle** (`ctrl`) — registro, PIN, comandos. Porta do console: 9303.
2. **Dados** (`data`) — vídeo, áudio, controle do jogo. Porta do console: 9297.

Antes de cada uma, o chiaki precisa descobrir seu próprio endereço externo (IP e porta que o NAT dá para ele). Ele faz isso perguntando a servidores **STUN**. Só depois troca candidatos com o console via PSN e "fura" o NAT.

## O que vimos

O controle conectou; o vídeo não:

```
[I] >> Punched hole for control connection!            ← controle ok
...
[W] Failed to get external address from stun.smslisto.com:3478, retrying with another STUN server...
[W] Failed to get external address from stun.freevoipdeal.com:3478, retrying...
[W] Failed to get external address from stun.voipbuster.com:3478, retrying...
[W] Failed to get external address from stun.kotter.net:3478, retrying...
[W] Failed to get external address from stun.voipconnect.com:3478, retrying...
[W] Failed to get external address from stun.easyvoip.com:3478, retrying...
[I] >> Punched hole for data connection!               ← ~35 s depois
[I] Takion connecting (version 7)
[E] Takion recv failed: Conexão recusada
[E] Takion failed to receive init ack
[E] Senkusha Takion connect failed
```

"Conexão recusada" num socket UDP significa que chegou um ICMP *port unreachable*: alguém no caminho disse "essa porta não existe". Vindo tão rápido (~6 ms por tentativa), e só depois de 35 s de STUN, a leitura é: o console abriu a porta, esperou, **desistiu** e fechou; quando o pacote do notebook chegou, o roteador de casa respondeu que não havia mais nada ali.

## De onde vêm esses servidores

O chiaki-ng não usa uma lista fixa. Em tempo de execução ele baixa:

```
https://raw.githubusercontent.com/pradt2/always-online-stun/master/valid_hosts.txt
```

e percorre a lista de cima para baixo até juntar respostas suficientes. Na rede corporativa testada, **os 7 primeiros** estavam bloqueados (ou mortos — `stun.freevoipdeal.com` nem resolve mais):

```
BLOQUEADO  stun.smslisto.com:3478
BLOQUEADO  stun.freevoipdeal.com:3478
BLOQUEADO  stun.voipbuster.com:3478
BLOQUEADO  stun.kotter.net:3478
BLOQUEADO  stun.voipconnect.com:3478
BLOQUEADO  stun.easyvoip.com:3478
BLOQUEADO  stun.sipdiscount.com:3478
OK         stun.cellmail.com:3478
OK         stun.dcalling.de:3478
...
```

Isso é típico de firewall corporativo: permite UDP para destinos "conhecidos" (Google, Cloudflare) e bloqueia o resto. Os servidores de VoIP gratuitos caem no resto.

## Teste a SUA rede

`make check` faz isso. Manualmente, para qualquer host:

```python
import socket, struct, os
def stun(host, port=3478):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); s.settimeout(3)
    s.sendto(struct.pack('>HHI12s', 1, 0, 0x2112A442, os.urandom(12)), (host, port))
    s.recvfrom(1024)          # levanta exceção se bloqueado
    return "OK"
print(stun("stun.smslisto.com"))       # bloqueado na rede testada
print(stun("stun.cloudflare.com"))     # OK
```

Se os primeiros da lista falham e `stun.cloudflare.com` responde, você está no mesmo caso.

## A correção: redirecionar só os bloqueados

O script testa os primeiros N hosts da lista e, para cada um **que falhar**, adiciona uma linha em `/etc/hosts` apontando para o STUN da Cloudflare:

```
# >>> chiaki-ng-remote-play-kit STUN
162.159.207.0 stun.smslisto.com
162.159.207.0 stun.freevoipdeal.com
...
# <<< chiaki-ng-remote-play-kit STUN
```

Efeito: quando o chiaki pergunta a `stun.smslisto.com`, a resposta vem da Cloudflare em ~4 ms. A fase de dados cai de ~35 s para ~1 s. O console ainda está esperando. Vídeo conecta.

### Por que é seguro

- STUN só devolve "qual é o seu IP:porta visto de fora". Não passa tráfego do jogo, não vê conteúdo. Cloudflare respondendo em vez de um provedor VoIP obscuro não muda nada do que o chiaki faz depois.
- Afeta **só** esses hostnames. Nenhum outro programa usa `stun.smslisto.com`.
- É um bloco delimitado com marcadores; o `--revert` remove exatamente ele.
- Em casa, na rede normal, é inofensivo: a Cloudflare responde de qualquer lugar.

### O que NÃO faz

- Não abre porta, não desliga firewall, não muda rota.
- Não resolve NAT simétrico (ver abaixo).
- Não resolve bloqueio **total** de UDP. Se `stun.cloudflare.com` também falhar, a rede não deixa UDP passar; hotspot do celular é a saída.

## Tipo de NAT: quando nem isso resolve

Holepunch depende do NAT ser previsível. `make check` mede:

- **Cone / mapeamento consistente** — a mesma porta externa para qualquer destino. Holepunch funciona. Foi o caso da rede testada (e ainda preservava a porta local, o melhor cenário).
- **Simétrico** — porta externa diferente para cada destino. O console não consegue adivinhar onde acertar. Aí o chiaki tenta *port guessing* (`port_guessing_enabled=true` na config; o kit deixa ligado por padrão — só é acionado quando necessário), mas a taxa de sucesso é baixa. Solução realista: outra rede (hotspot 4G/5G).

## Como saber se este é o seu caso

No log: várias linhas `Failed to get external address from stun.*` seguidas **e** `Takion recv failed: Conexão recusada`. Sem log: `make check` lista os STUN bloqueados.

Se não há STUN falhando e o vídeo ainda é recusado, o problema é outro (NAT simétrico, ou o roteador de casa) — veja [06-troubleshooting.md](06-troubleshooting.md).

## Como reverter

```sh
scripts/30-stun-redirect.sh --revert
```
Remove o bloco do `/etc/hosts` (há backup em `/etc/hosts.bak-chiaki-kit-*`).
