# chiaki-ng Remote Play Kit

[![Licença: MIT](https://img.shields.io/badge/licen%C3%A7a-MIT-blue.svg)](LICENSE)
[![CI](https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/actions/workflows/ci.yml/badge.svg)](https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/actions/workflows/ci.yml)

Kit que faz o **Remote Play do PS5 funcionar no Arch Linux fora de casa** (pela internet, via PSN), corrigindo três problemas que a instalação comum do chiaki-ng tem hoje: um certificado que a Sony não envia, um pacote do AUR que está com código antigo, e servidores de rede que muitos wifis bloqueiam.

É para quem tem um PS5 (especialmente **PS5 Pro**), usa Arch Linux ou derivado (Manjaro, EndeavourOS) e quer jogar do notebook estando longe do console. Você não precisa entender nada de rede — só saber abrir um terminal e colar comandos.

---

## Você precisa disto se…

- O chiaki-ng fica **preso para sempre** na tela *"Cancelling connection with console over PSN…"* e você precisa matar o programa.
- Ele até começa a conectar, mas **cai com "Failed to start session"** ou *"conexão recusada"* antes de aparecer imagem.
- Em casa funciona, mas **no wifi do trabalho, da faculdade ou de um hotel nunca conecta**.

Se em casa, na mesma rede do PS5, já funciona e você só joga em casa — você **não** precisa deste kit.

---

## O que ele faz (e o que NÃO faz)

**Faz:**

1. Instala um certificado intermediário **público** da COMODO que o servidor da Sony esquece de enviar (sem ele, a conexão segura falha).
2. Compila e instala o chiaki-ng a partir de um **commit oficial fixado** que contém a correção para o PS5 Pro (o pacote `chiaki-ng` do AUR aponta para código de 2025, sem essa correção).
3. **Opcionalmente**, redireciona os servidores STUN que a *sua* rede bloqueia para um que funciona (Cloudflare) — só se o diagnóstico mostrar que precisa.

**Não faz:**

- Não mexe no seu firewall nem desliga nenhuma proteção.
- Não guarda, não pede e não vê sua senha da PSN nem o PIN do console. Isso você digita na tela do próprio chiaki.
- Não altera o código do chiaki-ng. Ele compila o projeto oficial, sem modificações.

Cada mudança que o kit faz no sistema é **reversível** com um comando: `make revert`.

---

## Instalação em 5 minutos

> Tempo real: ~5 minutos de atenção sua, mais ~15 minutos de compilação em que você pode fazer outra coisa.

**1. Baixe o kit**

```bash
git clone https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit.git
cd chiaki-ng-remote-play-kit
```

**2. Rode o diagnóstico** — este passo **só lê**, não muda nada no seu computador:

```bash
make check
```

Você vai ver uma lista com `[ ok ]` e `[warn]`. No final, um veredito dizendo quais dos três problemas existem na sua máquina/rede. Guarde essa informação: ela diz se você vai precisar do passo 4.

**3. Instale** — aqui o kit **vai pedir sua senha de sudo**:

```bash
make install
```

O sudo é usado para exatamente duas coisas: copiar o certificado para a pasta de certificados do sistema e instalar o pacote compilado com o `pacman`. A compilação leva uns 15 minutos. Quando terminar, você verá `Instalação concluída`.

**4. Só se o passo 2 avisou "STUN bloqueado"** — redirecione os servidores que sua rede bloqueia:

```bash
make stun
```

Ele testa cada servidor, redireciona apenas os que falham e mostra quais foram. Se o `make check` não falou em STUN, **pule este passo**.

**5. Abra o chiaki-ng** (pelo menu de aplicativos ou digitando `chiaki` no terminal).

**6. Faça login na PSN** — no chiaki, vá em *Settings → PSN → Login*. Abre uma janela do navegador com o login da Sony. Entre com a sua conta. Ao terminar, o chiaki mostra seu nome de usuário na tela de configurações.

**7. Registre o console** — na tela inicial, clique em *Register* e siga as instruções. Isto precisa ser feito **uma vez, com você em casa, na mesma rede do PS5** (ou com o console já aparecendo na lista via PSN). O PS5 mostra um código de 8 dígitos na tela dele; você digita no chiaki.

**8. Conecte** — clique no seu PS5 na tela inicial. Ele vai pedir o **PIN de login do seu perfil no PS5** (o de 4 dígitos que você digita para entrar no console). Em uns 10 a 20 segundos aparece a imagem do jogo.

Se o console estava em modo de repouso: a primeira tentativa pode voltar para a tela inicial — isso é ele acordando. **Clique de novo.**

---

## Deu errado?

```bash
make doctor
```

Ele lê o último registro de conexão do chiaki e responde em português o que aconteceu, com uma destas respostas:

| O doctor diz… | Significa | Faça |
|---|---|---|
| **Certificado faltando** | O passo 3 não foi aplicado ou foi desfeito | `make install-ca` |
| **Binário antigo** | Está rodando o chiaki-ng do AUR, sem o fix | `make build` |
| **STUN bloqueado** | Sua rede bloqueia os servidores da lista | `make stun` |
| **Console não respondeu** | O PS5 estava em repouso e só acordou | Tente conectar de novo |
| **PIN incorreto** | O PIN do perfil está errado | Confira no PS5: *Ajustes → Usuários e Contas → Informações de Login → Código de Acesso* |
| **Conectou** | Está tudo certo | Jogue |

Detalhes de cada caso, com os trechos exatos de log: [docs/06-troubleshooting.md](docs/06-troubleshooting.md).

---

## Perguntas frequentes

**É seguro instalar um certificado no meu sistema?**
Sim. É um certificado **intermediário público** da COMODO/Sectigo — o mesmo que qualquer navegador baixa sozinho quando visita um site. Ele já é confiado pelo seu sistema indiretamente (o root está instalado); o kit só torna essa confiança explícita para programas que não sabem baixar a cadeia sozinhos, como o curl. Ele não dá acesso a nada seu. O hash está em [certs/README.md](certs/README.md) e o script confere antes de instalar. `make revert` remove.

**Preciso compilar? Demora?**
Sim, uns 15 minutos na maioria dos computadores. É o preço de ter a versão certa. Se você não quer esperar, cada [Release](https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/releases) tem um pacote pré-compilado: `make build` detecta e oferece usá-lo (`scripts/20-build-chiaki-ng.sh --prebuilt`).

**Funciona no Ubuntu / Debian / Fedora?**
Não. O kit foi escrito e testado só para **Arch Linux e derivados**. Os caminhos de certificado e o sistema de pacotes são diferentes nas outras distros.

**Funciona fora de casa mesmo?**
Sim — foi exatamente o cenário em que ele foi testado: notebook no wifi de uma empresa, PS5 Pro em casa. Se a sua rede for **muito** restrita (bloqueia UDP inteiramente), nem o redirecionamento de STUN salva; nesse caso use o 4G do celular como roteador.

**Que PIN é esse que ele pede?**
O **PIN de login do seu perfil no PS5** — os 4 dígitos que você digita para entrar na sua conta no console. Não é a senha da PSN, nem o código de 8 dígitos do registro. Se você não usa PIN no console, ele não vai pedir.

**Coloquei o PS5 em repouso e agora não conecta.**
Normal. A primeira tentativa acorda o console e dá timeout depois de 30 segundos (volta para a tela inicial). A segunda ou terceira conecta. Se nunca conectar, confira no PS5 se estão ligados *Permanecer conectado à internet* e *Ativar ligar o PS5 pela rede* em *Ajustes → Sistema → Economia de energia*.

**Isso é um fork do chiaki-ng?**
Não. O kit compila o [chiaki-ng oficial](https://github.com/streetpea/chiaki-ng), sem nenhuma alteração no código, a partir de um commit fixado que já contém as correções. Quando o pacote do AUR for atualizado, o kit deixa de ser necessário para esse item.

**Posso desfazer tudo?**
Sim: `make revert` remove o certificado e o redirecionamento de STUN. Para remover o programa: `sudo pacman -R chiaki-ng-git`. Detalhes em [docs/99-reverter-tudo.md](docs/99-reverter-tudo.md).

---

## Para a sua IA

Se você vai pedir para uma IA (Claude Code, Cursor, etc.) fazer a instalação por você, aponte-a para o arquivo [AGENTS.md](AGENTS.md). Ele tem a ordem de execução, as verificações de cada passo e o que ela **nunca** deve fazer.

---

## Como funciona por dentro

O Remote Play pela internet passa por três etapas: uma conexão segura com os servidores da Sony (WebSocket), a descoberta do seu endereço na internet (STUN) e a abertura de um caminho direto até o console (*holepunch*). Cada um dos três problemas que o kit corrige derruba uma dessas etapas de um jeito enganoso — o erro que aparece nunca aponta a causa real. A história completa, com os trechos de log e as evidências, está em [docs/01-o-problema.md](docs/01-o-problema.md).

Documentação por assunto:

- [01 — O problema](docs/01-o-problema.md) · [02 — Certificado PSN](docs/02-certificado-psn.md) · [03 — Build](docs/03-build.md)
- [04 — Rede restrita](docs/04-rede-restrita.md) · [05 — Primeira conexão](docs/05-primeira-conexao.md) · [06 — Troubleshooting](docs/06-troubleshooting.md) · [07 — Controle DualSense](docs/07-controle-dualsense.md)
- [99 — Reverter tudo](docs/99-reverter-tudo.md)

---

## Créditos e licença

- [chiaki-ng](https://github.com/streetpea/chiaki-ng), de streetpea e colaboradores — AGPL-3.0-only com exceção OpenSSL. É o programa de verdade; este kit só o instala direito.
- [always-online-stun](https://github.com/pradt2/always-online-stun), de pradt2 — a lista de servidores STUN que o chiaki-ng consulta.
- [Cloudflare](https://developers.cloudflare.com/calls/turn/) — pelo servidor STUN público usado no redirecionamento.

Os scripts e a documentação deste kit são [MIT](LICENSE). O pacote pré-compilado nas Releases é um build inalterado do commit oficial indicado em [packaging/arch/PKGBUILD](packaging/arch/PKGBUILD).
