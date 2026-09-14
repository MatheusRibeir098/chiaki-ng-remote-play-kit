# 03 — Build: por que o pacote do AUR não serve e qual commit usar

**Em uma frase:** o pacote `chiaki-ng` do AUR se chama 1.10.0 mas compila código de agosto/2025, anterior ao fix que aceita o `customData1` de 17 bytes do PS5 Pro; o kit compila (ou instala pré-compilado) um commit de setembro/2026 que tem o fix.

Script: `scripts/20-build-chiaki-ng.sh` · Atalho: `make build` · Receita: `packaging/arch/PKGBUILD`

## O sintoma

```
[I] >> Started session
[E] chiaki_holepunch_session_start: Failed to decode "customData1": '<redacted>' with error Unknown
[E] !! Failed to start session
```

Quando o console entra na sessão PSN, ele escreve um campo `customData1`. O PS5 Pro (firmware 13600007 no relato da issue) devolve **17 bytes** depois de decodificar; versões antigas do chiaki exigem exatamente 16 e rejeitam.

Issue upstream: https://github.com/streetpea/chiaki-ng/issues/810

## A confusão da versão

O mantenedor fechou a issue em 6/set/2026 com *"That was already fixed a while ago try 1.10"*. Está certo — o fix existe desde 19/mar/2026 (commit `254d37ae8`, *"Change custom decode function to accept up to 4 extra characters"*) e está na tag `v1.10.0` (3/abr/2026).

O problema é o **PKGBUILD do AUR** `chiaki-ng`:

```sh
pkgver=1.10.0
_commit="3f8fd712cbc0becd3a5ea588340d72bf451c12b5"
source=(git+"https://github.com/streetpea/${pkgname}.git?signed#commit=${_commit}")
```

Esse commit é de **10/ago/2025** — 107 commits *antes* do fix. Então `pacman -Q` diz `chiaki-ng 1.10.0-2`, o log diz `Chiaki Version 1.9.9`, e o bug está lá. Quem lê a resposta do mantenedor, olha a versão instalada e conclui que o problema é outro.

Verificação que fizemos:
```
$ gh api repos/streetpea/chiaki-ng/compare/254d37ae8...3f8fd712cbc0becd3a5ea588340d72bf451c12b5 --jq '{status,behind_by}'
{"status":"behind","behind_by":107}
```

## O código, antes e depois

Função `decode_customdata1` em `lib/src/remote/holepunch.c`, no commit corrigido:

```c
#define CUSTOMDATA1_EXTRA_BYTES_MAX 4
...
    if (round2_len < out_len)
        return CHIAKI_ERR_UNKNOWN;
    if (round2_len > out_len + CUSTOMDATA1_EXTRA_BYTES_MAX)
        return CHIAKI_ERR_UNKNOWN;
    if (round2_len > out_len)
        CHIAKI_LOGI(log, "decode_customdata1: customData1 contains %zu extra byte(s); ignoring extras", round2_len - out_len);
    memcpy(out, customdata1_round2, out_len);
```

Com 17 bytes e `out_len = 16`: passa (17 ≤ 20), loga *"contains 1 extra byte(s); ignoring extras"* e segue. No código de 2025 a comparação era estrita e devolvia `CHIAKI_ERR_UNKNOWN`.

## O que o kit compila

Commit fixado: **`0e16950165f06e5c3291537c2eeba6e852be7120`** (7/set/2026, main). Foi o build validado de ponta a ponta — conectou, streamou, acordou o console do repouso.

Diferenças do `PKGBUILD` do kit em relação ao `chiaki-ng-git` do AUR:

| | AUR `chiaki-ng-git` | Kit |
|---|---|---|
| `source` | HEAD do main (muda a cada build) | `#commit=0e16950…` (reproduzível) |
| `pkgver` | calculado no build | fixo `2176_2026.09.07` |
| `pkgname` | `chiaki-ng-git` | **igual** — de propósito |

Manter o mesmo `pkgname` faz um futuro `yay -Syu` oferecer o `chiaki-ng-git` do AUR como atualização normal. Isso é desejado: qualquer commit do main mais novo que março/2026 também tem o fix. Só **não volte** para o pacote `chiaki-ng` (sem `-git`) enquanto o pin dele não for corrigido.

## Pré-compilado ou compilar?

- **Pré-compilado** (`dist/` nas Releases do GitHub): `sudo pacman -U chiaki-ng-git-2176_2026.09.07-1-x86_64.pkg.tar.zst`. Instala em segundos. É o build inalterado do commit acima; o `SHA256SUMS` acompanha.
- **Compilar**: `make build` roda `makepkg -si` em `packaging/arch/`. Leva 10–20 min e baixa `makedepends` (`cmake`, `python-protobuf`, `vulkan-headers`…). Use se preferir não confiar em binário de terceiros — é a mesma receita.

O script tenta o pré-compilado primeiro se ele estiver em `dist/`; senão compila.

Conflito esperado: o novo pacote **substitui** `chiaki-ng` ou `chiaki`. O `pacman` pergunta; o script responde por você depois de mostrar o que vai remover.

## Como saber se este é o seu caso

```sh
strings /usr/bin/chiaki | grep -c 'contains %zu extra byte'
```
`0` = binário sem o fix → `make build`. `1` = ok. Ou no log: `Failed to decode "customData1"`.

## Como reverter

```sh
sudo pacman -R chiaki-ng-git
```
E instale o que quiser no lugar. Não há mais nada a desfazer — o kit não altera o código do chiaki, só escolhe o commit.
