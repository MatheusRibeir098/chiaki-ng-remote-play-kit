#!/usr/bin/env bash
# Biblioteca comum dos scripts do kit. Carregar com:
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
#
# Convenções:
#   - DRY_RUN=1 (ou --dry-run) mostra o que faria sem executar nada com efeito.
#   - Nenhuma função ecoa segredos. Não passe tokens/PIN por aqui.
#   - Saída: 0 ok | 1 erro genérico | 2 pré-requisito ausente | 3 recusado pelo usuário

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export REPO_ROOT
DRY_RUN="${DRY_RUN:-0}"

# ---- cores (desligam se não for terminal) ----------------------------------
if [[ -t 1 ]]; then
  C_RED=$'\e[31m'
  C_GRN=$'\e[32m'
  C_YLW=$'\e[33m'
  C_BLU=$'\e[34m'
  C_DIM=$'\e[2m'
  C_OFF=$'\e[0m'
else
  C_RED=""
  C_GRN=""
  C_YLW=""
  C_BLU=""
  C_DIM=""
  C_OFF=""
fi

log_info() { printf '%s[info]%s %s\n' "$C_BLU" "$C_OFF" "$*"; }
log_ok() { printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
log_warn() { printf '%s[warn]%s %s\n' "$C_YLW" "$C_OFF" "$*" >&2; }
log_err() { printf '%s[erro]%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; }
die() {
  log_err "$*"
  exit 1
}

# ---- flags comuns ----------------------------------------------------------
# Uso: parse_common_flags "$@"; set -- "${REMAINING_ARGS[@]}"
REMAINING_ARGS=()
parse_common_flags() {
  REMAINING_ARGS=()
  for a in "$@"; do
    case "$a" in
      --dry-run) DRY_RUN=1 ;;
      -h | --help)
        usage
        exit 0
        ;;
      *) REMAINING_ARGS+=("$a") ;;
    esac
  done
}

# ---- execução --------------------------------------------------------------
# run <cmd...>: executa, ou só mostra em dry-run.
run() {
  if [[ "$DRY_RUN" == "1" ]]; then
    printf '%s[dry-run]%s %s\n' "$C_DIM" "$C_OFF" "$*"
  else
    "$@"
  fi
}

# run_sudo <cmd...>: idem, com sudo. Avisa antes da primeira vez.
_SUDO_WARNED=0
run_sudo() {
  if [[ "$_SUDO_WARNED" == "0" ]]; then
    log_info "Os próximos passos precisam de sudo (alteram arquivos do sistema)."
    _SUDO_WARNED=1
  fi
  run sudo "$@"
}

# ---- pré-requisitos --------------------------------------------------------
need_cmd() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || {
      log_err "comando ausente: $c"
      return 2
    }
  done
}

require_arch() {
  if [[ ! -f /etc/arch-release ]] && ! grep -qiE 'ID_LIKE=.*arch|^ID=arch' /etc/os-release 2>/dev/null; then
    die "Este kit foi escrito e testado para Arch Linux e derivados (Manjaro, EndeavourOS). Distro atual não suportada."
  fi
}

# ---- utilidades ------------------------------------------------------------
# backup_file <path>: cria <path>.bak-chiaki-kit-<timestamp> (uma vez por execução).
backup_file() {
  local f="$1" b
  [[ -e "$f" ]] || return 0
  b="${f}.bak-chiaki-kit-$(date +%Y%m%d-%H%M%S)"
  run_sudo cp -a "$f" "$b"
  log_info "backup: $b"
}

# newest_chiaki_log: caminho do log de sessão mais recente do chiaki (ou vazio).
newest_chiaki_log() {
  local d="$HOME/.local/share/Chiaki/Chiaki/log"
  [[ -d "$d" ]] || return 0
  find "$d" -name '*.log' -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-
}

# confirm "<pergunta>": pede s/N; em dry-run assume sim.
confirm() {
  [[ "$DRY_RUN" == "1" ]] && return 0
  local r
  read -r -p "$1 [s/N] " r
  [[ "$r" =~ ^[sSyY]$ ]] || {
    log_warn "cancelado pelo usuário"
    exit 3
  }
}

usage() { echo "uso: $(basename "$0") [--dry-run] [--help]"; }
