# packaging/arch/

`PKGBUILD` do **chiaki-ng fixado no commit que contém o fix do PS5 Pro**. É o que `make build` usa.

## Usar manualmente

```bash
cd packaging/arch
makepkg -si          # baixa o commit fixado, compila (~15 min) e instala com pacman
```

Se já existir `chiaki` ou `chiaki-ng` instalado, o pacman pergunta se remove — responda sim. O pacote se chama `chiaki-ng-git`, provê `chiaki` e conflita com `chiaki` e `chiaki-ng`.

## Por que o commit é fixado

O pacote `chiaki-ng` do AUR declara `pkgver=1.10.0`, mas o `_commit` que ele baixa é de **agosto de 2025** — anterior ao commit `254d37ae8` (março/2026), que ensinou o `decode_customdata1` a aceitar até 4 bytes extras. Um PS5 Pro devolve 17 bytes onde a versão antiga exige 16, e a conexão morre com `Failed to decode "customData1"`. Ver `docs/03-build.md` e a [issue #810](https://github.com/streetpea/chiaki-ng/issues/810) do upstream.

Fixamos o commit `0e16950165f06e5c3291537c2eeba6e852be7120` (2026-09-07) porque foi o build validado de ponta a ponta. Qualquer commit do `main` a partir de `254d37ae8` serve.

Mantemos o nome `chiaki-ng-git` de propósito: quando o AUR publicar um `chiaki-ng-git` mais novo, o `yay -Syu` atualiza por cima e a pessoa continua na linha que tem o fix.

## Atualizar o pin

1. Escolha um commit do `main` do [streetpea/chiaki-ng](https://github.com/streetpea/chiaki-ng/commits/main) que seja descendente de `254d37ae8` (qualquer um mais novo que 2026-03-19). Confirme: `git merge-base --is-ancestor 254d37ae8 <commit>`.
2. Edite `PKGBUILD`: `_commit=<sha completo>` e `pkgver=<commits>_<AAAA.MM.DD>` — obtenha com `git rev-list --count <commit>` e `git log -1 --date=short --format=%cd <commit>` no clone do upstream. Volte `pkgrel=1`.
3. Teste: `makepkg -si`, abra o chiaki, conecte via PSN e confirme no log a linha `decode_customdata1: customData1 contains N extra byte(s); ignoring extras` seguida de `StreamConnection successfully received streaminfo`. Só então commite e atualize o `CHANGELOG.md`.

## Gerar e publicar o pré-compilado na Release

O CI valida o PKGBUILD mas **não compila** (levaria ~20 min por push). O pacote das Releases é gerado localmente:

```bash
cd packaging/arch
makepkg -Cf                                   # build limpo
mkdir -p ../../dist && mv chiaki-ng-git-*-x86_64.pkg.tar.zst ../../dist/
cd ../../dist && sha256sum *.pkg.tar.zst > SHA256SUMS

gh auth switch --user MatheusRibeir098        # conta pessoal
gh release create v0.1.0 dist/*.pkg.tar.zst dist/SHA256SUMS \
  --title "v0.1.0" --notes-file CHANGELOG.md
```

`dist/` está no `.gitignore`: o binário nunca entra no histórico do git, só na Release. Quem baixa confere com `sha256sum -c SHA256SUMS`. O script `20-build-chiaki-ng.sh --prebuilt` faz exatamente isso antes de instalar.

Licença: o pacote é um build **inalterado** do commit fixado do chiaki-ng (AGPL-3.0-only com exceção OpenSSL); o código-fonte correspondente é o próprio repositório upstream nesse commit, referenciado pelo `_commit` acima.
