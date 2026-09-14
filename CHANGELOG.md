# Changelog

Todas as mudanças relevantes deste kit. Formato: [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/). Versionamento: [SemVer](https://semver.org/lang/pt-BR/).

## [Unreleased]

### Added

- `docs/07-controle-dualsense.md` — DualSense "conectado" mas ignorado por Bluetooth (`!bonded`, sem link key): diagnóstico, re-pareamento e acesso hidraw para vibração/gatilhos.

## [0.1.0] - 2026-09-14

### Added

- `scripts/00-check-env.sh` — diagnóstico de distro, dependências, TLS do endpoint de push da PSN, alcance dos servidores STUN e tipo de NAT; emite veredito antes de qualquer alteração (`--json` disponível).
- `scripts/10-install-ca-intermediate.sh` — instala a intermediária `COMODO RSA Domain Validation Secure Server CA` no trust store do sistema (baixa pelo AIA, confere SHA-256, fallback em `certs/`); `--revert`.
- `scripts/20-build-chiaki-ng.sh` — compila e instala o chiaki-ng pelo PKGBUILD fixado (`--build`) ou instala o pré-compilado da Release conferindo o hash (`--prebuilt`).
- `scripts/30-stun-redirect.sh` — testa a lista `always-online-stun`, redireciona no `/etc/hosts` apenas os servidores que a rede local bloqueia (`--all` para todos); `--revert`.
- `scripts/40-apply-config.sh` — aplica `config/Chiaki.conf.example` sem sobrescrever segredos existentes; `--verbose-log on|off`.
- `scripts/90-doctor.sh` — lê o último log do chiaki e classifica a falha (certificado, binário antigo, STUN, console em repouso, PIN); `--json`, `--log <arquivo>`.
- `scripts/lib/common.sh` — log, `--dry-run`, backups com carimbo de tempo, detecção de Arch, sudo com aviso.
- `packaging/arch/PKGBUILD` — chiaki-ng-git fixado no commit `0e16950` (2026-09-07), com `CHIAKI_USE_SYSTEM_CURL=ON`.
- `certs/` — intermediária COMODO pública com hash e origem documentados.
- `docs/01`–`06` e `99` — a história dos três problemas com trechos reais de log, o porquê de cada correção, primeira conexão, troubleshooting e reversão.
- `README.md` para pessoas e `AGENTS.md` para agentes de IA.
- `Makefile` com os alvos `check | install-ca | build | stun | config | doctor | install | revert | lint`.
- CI (GitHub Actions): shellcheck, shfmt, `bash -n`, varredura de segredos, `namcap` + `makepkg -o` em container Arch, verificação de links da documentação.
- Release com o pacote `chiaki-ng-git-2176_2026.09.07-1-x86_64.pkg.tar.zst` pré-compilado e `SHA256SUMS`.

### Notas

- Commit upstream fixado: `0e16950165f06e5c3291537c2eeba6e852be7120` (contém `254d37ae8`, o fix do `customData1`).
- Validado de ponta a ponta em Arch Linux, com PS5 Pro, a partir de rede corporativa que bloqueia parte dos servidores STUN — inclusive acordar o console do modo de repouso.
- Só Arch Linux e derivados. Outras distros não são suportadas nesta versão.

[Unreleased]: https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/releases/tag/v0.1.0
