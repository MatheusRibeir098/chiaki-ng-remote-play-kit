# 05 — Primeira conexão: login, registro, PIN e o console em repouso

**Em uma frase:** depois das correções, ainda há três passos humanos na GUI — entrar na conta PSN, registrar o console e digitar o passcode do perfil — e um comportamento que parece falha mas não é: a primeira tentativa com o console em repouso só o acorda.

Nenhum script faz esta parte. É na interface do chiaki-ng, e envolve **seus** dados — nada disso vai para o repositório.

## Antes de começar, no PS5

Uma vez só, com o console na sua frente:

1. **Ajustes → Sistema → Remote Play → Ativar Remote Play**: ligado.
2. **Ajustes → Sistema → Economia de energia → Recursos disponíveis no modo de repouso**:
   - *Permanecer conectado à internet*: ligado
   - *Ativar ligar o PS5 pela rede*: ligado
   Sem o segundo, o console nunca acorda de fora.
3. **Ajustes → Usuários e Contas → Informações de Login → Código de Acesso**: anote (ou defina) o passcode de 4 dígitos do seu perfil. É ele que o chiaki vai pedir.

## No chiaki-ng

### 1. Login PSN

Na tela inicial, o ícone de usuário / *"PSN Login"*. O app abre uma URL da Sony no seu navegador; você faz login com sua conta PSN; a Sony redireciona para uma página `remoteplay.dl.playstation.net/remoteplay/redirect?code=...`. Cole essa URL de volta no chiaki. Ele troca o código por um token e guarda em `~/.config/Chiaki/Chiaki.conf`.

Esse token é **seu**. É por isso que `Chiaki.conf` está no `.gitignore` do kit.

### 2. Registro do console

Duas formas:

- **Na mesma rede do PS5** (casa): o console aparece automaticamente por descoberta; clique em registrar, digite o PIN de 8 dígitos que o PS5 mostra em *Ajustes → Sistema → Remote Play → Vincular dispositivo*.
- **Via PSN, de qualquer lugar**: *"Register via PSN"* — o chiaki lista os consoles da sua conta e registra pela internet.

Depois disso o console fica com **duas entradas** na tela inicial: uma pelo IP local (só funciona em casa) e uma **via PSN** (funciona de qualquer lugar). Fora de casa, clique na via PSN.

### 3. Conectar e o PIN

Ao conectar via PSN, o console pede um PIN de **4 dígitos**. Atenção ao que é:

| É | Não é |
|---|---|
| O **passcode do seu perfil no PS5** — o código que você digita para entrar no seu usuário no console | A senha da conta PSN |
| | O PIN de 8 dígitos do registro |

No log aparece assim quando erra:
```
[I] Ctrl received Login message: PIN incorrect
[I] Login PIN was incorrect, requested again by Ctrl
```
Exemplo fictício de PIN nos docs: `1234`. O seu é o que está em *Código de Acesso*.

**Cuidado:** cada erro conta como tentativa de login errada no console. Errar muitas vezes seguidas pode bloquear o perfil temporariamente. Se não tem certeza, confirme no PS5 antes de chutar.

## Console em repouso: "voltou para a tela inicial" é normal

Com o PS5 em repouso, o fluxo típico é:

```
tentativa 1:  [E] wait_for_notification: Timed out waiting for holepunch session messages
              [E] chiaki_holepunch_session_start: Timed out waiting for holepunch session start notifications.
              [E] !! Failed to start session          ← app volta à tela inicial após 30 s
tentativa 2:  [I] >> Started session
              [I] >> Punched hole for data connection!
              [I] StreamConnection successfully received streaminfo   ← jogando
```

A tentativa 1 **acordou** o console; ele leva 10–30 s para subir, mais do que o chiaki espera. A tentativa seguinte encontra o console pronto. Não é defeito. Se a 3ª também falhar, revise os ajustes de repouso do item "Antes de começar".

## O que esperar quando funciona

- Janela em fullscreen, vídeo em segundos.
- No log: `Takion connected`, `Senkusha successfully received bang`, `StreamConnection successfully received streaminfo`.
- `Senkusha MTU 1454 success` é o teste de tamanho de pacote — informativo.

## Como saber se este é o seu caso

Você já rodou `make install-ca` e `make build`, `make check` está limpo, e o log mostra `PIN incorrect` ou `Timed out waiting for holepunch session start`. Nenhum dos dois é bug do kit: um é o passcode, o outro é o console acordando.

## Como reverter

Não há nada a reverter no sistema. Para "desfazer" o login PSN e o registro: apague `~/.config/Chiaki/Chiaki.conf` (ou só as chaves `psn_*` e `[registered_hosts]`). O kit nunca toca nessas chaves.
