#!/usr/bin/env bash
# 00-check-env.sh — diagnóstico READ-ONLY do ambiente e da rede para o Remote Play via PSN.
# Não altera nada. Rode SEMPRE antes dos outros scripts: ele diz quais dos três problemas
# conhecidos existem nesta máquina/rede e qual script rodar em seguida.
#
# Verifica:
#   a. distro Arch-like e dependências de build
#   b. chiaki instalado e se o binário tem o fix do customData1 (PS5 Pro, issue #810)
#   c. TLS do endpoint de push do PSN (intermediária COMODO presente?)
#   d. STUN: quantos servidores da lista que o chiaki usa estão bloqueados nesta rede
#   e. tipo de NAT (cone x simétrico)

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--json] [--help]

Diagnóstico read-only. Imprime um relatório por item e a linha final "PRÓXIMO PASSO".
  --json   saída em JSON (uma linha), para consumo por ferramentas/IA
USAGE
}

JSON=0
parse_common_flags "$@"
for a in "${REMAINING_ARGS[@]}"; do
  case "$a" in
    --json) JSON=1 ;;
    *) die "argumento desconhecido: $a (veja --help)" ;;
  esac
done

STUN_PY="$REPO_ROOT/scripts/lib/stun.py"
PSN_PUSH_HOST="44-232-96-0-pushcl.np.communication.playstation.net"
CA_ANCHOR="/etc/ca-certificates/trust-source/anchors/comodo-rsa-dv-secure-server-ca.crt"
BUILD_DEPS=(git cmake python-protobuf python-setuptools vulkan-headers)

# Acumuladores para o relatório/JSON
declare -A R
NEXT_STEPS=()

section() { [[ "$JSON" == "1" ]] || printf '\n%s== %s ==%s\n' "$C_BLU" "$1" "$C_OFF"; }
say_ok() {
  R["$1"]="ok"
  [[ "$JSON" == "1" ]] || log_ok "$2"
}
say_warn() {
  R["$1"]="warn"
  [[ "$JSON" == "1" ]] || log_warn "$2"
}
say_fail() {
  R["$1"]="fail"
  [[ "$JSON" == "1" ]] || log_err "$2"
}

# ---- a. distro e dependências ---------------------------------------------
section "a. Sistema"
require_arch
say_ok distro "Arch Linux (ou derivado) detectado"

missing=()
for d in "${BUILD_DEPS[@]}"; do
  pacman -Qq "$d" >/dev/null 2>&1 || missing+=("$d")
done
if ((${#missing[@]} == 0)); then
  say_ok build_deps "dependências de build presentes"
else
  say_warn build_deps "dependências de build ausentes: ${missing[*]} (o 20-build instala)"
fi
R[build_deps_missing]="${missing[*]:-}"

if command -v makepkg >/dev/null; then
  say_ok makepkg "makepkg disponível$(command -v yay >/dev/null && echo ' (yay também)')"
else
  say_fail makepkg "makepkg ausente — instale base-devel"
  NEXT_STEPS+=("sudo pacman -S --needed base-devel")
fi

# ---- b. chiaki instalado e fix do customData1 -----------------------------
section "b. chiaki-ng"
pkg="$(pacman -Q chiaki-ng-git 2>/dev/null || pacman -Q chiaki-ng 2>/dev/null || true)"
if [[ -z "$pkg" ]]; then
  say_fail chiaki_pkg "chiaki não instalado"
  R[chiaki_fix]="absent"
  NEXT_STEPS+=("scripts/20-build-chiaki-ng.sh")
else
  R[chiaki_pkg_name]="$pkg"
  # grep sem -q: com pipefail, `grep -q` sai no 1º match e o `strings` morre de SIGPIPE (falso negativo)
  fix_marker=""
  [[ -x /usr/bin/chiaki ]] && fix_marker="$(strings /usr/bin/chiaki 2>/dev/null | grep -F 'contains %zu extra byte' || true)"
  if [[ -n "$fix_marker" ]]; then
    say_ok chiaki_fix "instalado: $pkg — binário COM o fix do customData1"
  else
    say_fail chiaki_fix "instalado: $pkg — binário SEM o fix (bug do PS5 Pro, issue #810)"
    NEXT_STEPS+=("scripts/20-build-chiaki-ng.sh")
  fi
fi

# ---- c. TLS do endpoint PSN -----------------------------------------------
section "c. Certificado do endpoint PSN"
if [[ -f "$CA_ANCHOR" ]]; then
  say_ok ca_anchor "âncora da intermediária COMODO presente"
else
  say_warn ca_anchor "âncora da intermediária COMODO ausente em $CA_ANCHOR"
fi
if need_cmd curl >/dev/null 2>&1; then
  ssl_rc="$(timeout 15 curl -sS -o /dev/null -w '%{ssl_verify_result}' "https://$PSN_PUSH_HOST/" 2>/dev/null || echo "net")"
  R[psn_ssl_verify_result]="$ssl_rc"
  case "$ssl_rc" in
    0) say_ok psn_tls "TLS do endpoint de push valida (ssl_verify_result=0)" ;;
    20 | 21)
      say_fail psn_tls "TLS falha (ssl_verify_result=$ssl_rc): intermediária COMODO ausente — o chiaki vai travar em 'Cancelling connection over PSN'"
      NEXT_STEPS+=("scripts/10-install-ca-intermediate.sh")
      ;;
    net) say_warn psn_tls "não consegui alcançar o endpoint (sem rede? proxy?)" ;;
    *) say_warn psn_tls "ssl_verify_result inesperado: $ssl_rc" ;;
  esac
else
  say_fail psn_tls "curl ausente"
fi

# ---- d. STUN ------------------------------------------------------------------
section "d. Servidores STUN nesta rede"
need_cmd python3 || exit 2
mapfile -t stun_hosts < <(python3 "$STUN_PY" list --count 20)
mapfile -t results < <(python3 "$STUN_PY" test --timeout 3 stun.cloudflare.com:3478 stun.l.google.com:19302 "${stun_hosts[@]}")

blocked_first7=0
blocked_hosts=()
for line in "${results[@]}"; do
  read -r status hp _ <<<"$line"
  for i in "${!stun_hosts[@]}"; do
    if [[ "${stun_hosts[$i]}" == "$hp" && "$status" != "OK" ]]; then
      blocked_hosts+=("$hp")
      if ((i < 7)); then ((blocked_first7++)) || true; fi
    fi
  done
  [[ "$JSON" == "1" ]] || printf '   %-8s %s\n' "$status" "$hp"
done
R[stun_blocked_first7]="$blocked_first7"
R[stun_blocked_total]="${#blocked_hosts[@]}"
if ((blocked_first7 >= 3)); then
  say_fail stun "rede restringe STUN: $blocked_first7 dos 7 primeiros bloqueados → fase de vídeo demora ~35s e o console desiste"
  NEXT_STEPS+=("scripts/30-stun-redirect.sh")
elif ((${#blocked_hosts[@]} > 0)); then
  say_warn stun "${#blocked_hosts[@]} servidor(es) STUN sem resposta, mas os primeiros respondem — provavelmente ok"
else
  say_ok stun "todos os STUN testados respondem"
fi

# ---- e. tipo de NAT ---------------------------------------------------------------
section "e. NAT"
nat_line="$(python3 "$STUN_PY" nat --timeout 4 2>/dev/null || true)"
read -r nat_type nat_ports <<<"$nat_line"
R[nat_type]="${nat_type:-unknown}"
case "${nat_type:-}" in
  cone) say_ok nat "NAT cone, mapeamento consistente (portas: $nat_ports) — holepunch favorável" ;;
  symmetric) say_warn nat "NAT simétrico (portas variam: $nat_ports) — holepunch difícil; teste em outra rede ou 4G" ;;
  *) say_warn nat "não foi possível determinar o tipo de NAT (UDP de saída bloqueado?)" ;;
esac

# ---- relatório final --------------------------------------------------------------
if [[ "$JSON" == "1" ]]; then
  {
    printf '{'
    first=1
    for k in "${!R[@]}"; do
      ((first)) || printf ','
      first=0
      printf '"%s":"%s"' "$k" "${R[$k]//\"/\\\"}"
    done
    printf ',"next_steps":['
    first=1
    for s in "${NEXT_STEPS[@]}"; do
      ((first)) || printf ','
      first=0
      printf '"%s"' "$s"
    done
    printf ']}\n'
  }
else
  echo
  if ((${#NEXT_STEPS[@]} == 0)); then
    log_ok "PRÓXIMO PASSO: nada a corrigir. Abra o chiaki, faça login na PSN e conecte."
  else
    # remove duplicatas preservando ordem
    mapfile -t uniq_steps < <(printf '%s\n' "${NEXT_STEPS[@]}" | awk '!seen[$0]++')
    log_info "PRÓXIMO PASSO: rode, nesta ordem:"
    for s in "${uniq_steps[@]}"; do echo "   $s"; done
  fi
fi
