#!/usr/bin/env bash
# 20-build-chiaki-ng.sh — instala o chiaki-ng em um commit que contém o fix do
# customData1 de 17 bytes (PS5 Pro; streetpea/chiaki-ng#810).
#
# Por que não `yay -S chiaki-ng`: o pacote chiaki-ng do AUR (pkgver 1.10.0) fixa
# um commit de ago/2025, anterior ao fix. Ver docs/03-build.md.
#
# Modos:
#   (padrão)    usa dist/*.pkg.tar.zst se existir e o SHA256SUMS bater; senão compila
#   --prebuilt  exige o pré-compilado (orienta a baixar da Release se ausente)
#   --build     força compilar a partir de packaging/arch/PKGBUILD (~10-20 min)

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--prebuilt | --build] [--dry-run] [--help]

  --prebuilt   instala dist/chiaki-ng-git-*.pkg.tar.zst (conferindo SHA256SUMS)
  --build      compila via makepkg a partir de packaging/arch/PKGBUILD
  (sem flag)   pré-compilado se disponível e íntegro; senão compila
USAGE
}

FIX_SIGNATURE='contains %zu extra byte'
PKGBUILD_DIR="$REPO_ROOT/packaging/arch"
DIST_DIR="$REPO_ROOT/dist"
RELEASE_HINT="https://github.com/MatheusRibeir098/chiaki-ng-remote-play-kit/releases"

mode="auto"
parse_common_flags "$@"
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"
for a in "$@"; do
  case "$a" in
    --prebuilt) mode="prebuilt" ;;
    --build) mode="build" ;;
    *) die "argumento desconhecido: $a (veja --help)" ;;
  esac
done

require_arch
need_cmd pacman sudo || exit 2

binary_has_fix() {
  [[ -x /usr/bin/chiaki ]] || return 1
  need_cmd strings >/dev/null 2>&1 || return 1
  # process substitution: com pipefail, `strings | grep -q` falharia por SIGPIPE ao casar cedo
  grep -qF -- "$FIX_SIGNATURE" <(strings /usr/bin/chiaki 2>/dev/null)
}

# Já está tudo certo? Sai cedo.
if pacman -Q chiaki-ng-git >/dev/null 2>&1 && binary_has_fix; then
  log_ok "chiaki-ng-git $(pacman -Q chiaki-ng-git | awk '{print $2}') já instalado e o binário contém o fix. Nada a fazer."
  exit 0
fi

# Conflito com o pacote velho do AUR: precisa sair antes (o prompt do pacman
# "Remover chiaki-ng? [s/N]" responde N com --noconfirm e aborta a instalação).
remove_old_aur_package() {
  if pacman -Q chiaki-ng >/dev/null 2>&1; then
    log_warn "O pacote 'chiaki-ng' do AUR ($(pacman -Q chiaki-ng | awk '{print $2}')) está instalado."
    log_warn "Apesar do número de versão, ele foi compilado de um commit de ago/2025, ANTERIOR ao fix — é ele que falha com seu PS5."
    confirm "Remover 'chiaki-ng' para instalar a versão corrigida?"
    run_sudo pacman -Rns --noconfirm chiaki-ng
  fi
}

find_prebuilt() {
  local pkg
  pkg="$(find "$DIST_DIR" -maxdepth 1 -name 'chiaki-ng-git-*-x86_64.pkg.tar.zst' 2>/dev/null | sort | tail -1)"
  [[ -n "$pkg" && -f "$DIST_DIR/SHA256SUMS" ]] || return 1
  (cd "$DIST_DIR" && sha256sum --check --ignore-missing --status SHA256SUMS) || {
    log_err "SHA256SUMS não confere para $(basename "$pkg") — arquivo corrompido ou adulterado. Não vou instalar."
    return 1
  }
  printf '%s\n' "$pkg"
}

install_prebuilt() {
  local pkg="$1"
  log_info "Pacote pré-compilado íntegro: $(basename "$pkg")"
  remove_old_aur_package
  run_sudo pacman -U --needed --noconfirm "$pkg"
}

build_from_source() {
  need_cmd makepkg git cmake || exit 2
  [[ "$(id -u)" -ne 0 ]] || die "makepkg não roda como root. Execute como usuário normal (ele pede sudo quando precisa)."
  [[ -f "$PKGBUILD_DIR/PKGBUILD" ]] || die "PKGBUILD não encontrado em $PKGBUILD_DIR"
  log_info "Compilando o chiaki-ng a partir de packaging/arch/PKGBUILD (commit fixado). Leva ~10-20 min."
  # makedepends explícitos: makepkg -s faria isso, mas assim o erro de rede aparece antes do build.
  run_sudo pacman -S --needed --noconfirm git cmake python-protobuf python-setuptools vulkan-headers
  remove_old_aur_package
  (cd "$PKGBUILD_DIR" && run makepkg -si --needed --noconfirm)
}

case "$mode" in
  prebuilt)
    if pkg="$(find_prebuilt)"; then
      install_prebuilt "$pkg"
    else
      log_err "Nenhum pré-compilado íntegro em $DIST_DIR."
      log_info "Baixe o .pkg.tar.zst e o SHA256SUMS da Release para dist/ e rode de novo:"
      log_info "  $RELEASE_HINT"
      log_info "  ex.: gh release download --repo MatheusRibeir098/chiaki-ng-remote-play-kit --dir dist/"
      log_info "Ou compile localmente: $(basename "$0") --build"
      exit 2
    fi
    ;;
  build)
    build_from_source
    ;;
  auto)
    if pkg="$(find_prebuilt)"; then
      install_prebuilt "$pkg"
    else
      log_info "Sem pré-compilado íntegro em dist/; vou compilar."
      build_from_source
    fi
    ;;
esac

# Validação final: a única prova que importa é a string do fix dentro do binário.
if [[ "$DRY_RUN" == "1" ]]; then
  log_info "(dry-run) pulando validação do binário"
  exit 0
fi
if binary_has_fix; then
  log_ok "chiaki-ng-git $(pacman -Q chiaki-ng-git 2>/dev/null | awk '{print $2}') instalado; binário contém o fix do customData1."
else
  die "Instalação terminou mas /usr/bin/chiaki NÃO contém o fix ('$FIX_SIGNATURE'). Verifique docs/03-build.md."
fi
