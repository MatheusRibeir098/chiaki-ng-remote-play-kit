#!/usr/bin/env bash
# 30-stun-redirect.sh — redireciona, no /etc/hosts, SÓ os servidores STUN que a rede atual
# bloqueia, apontando-os para stun.cloudflare.com (162.159.207.0).
#
# Por quê: o chiaki baixa a lista pradt2/always-online-stun e consulta os primeiros hosts.
# Em redes corporativas os primeiros costumam estar bloqueados; cada um gasta ~5s de timeout,
# a fase de vídeo atrasa ~35s e o console desiste ("Takion recv failed: Conexão recusada").
# Redirecionados, eles respondem em milissegundos. Ver docs/04-rede-restrita.md.
#
# Escopo: afeta APENAS como ESTES hostnames resolvem nesta máquina. Reversível com --revert.
# É opcional — rode 00-check-env.sh antes; se sua rede não bloqueia, não precisa disto.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--dry-run] [--all] [--revert] [--help]

Testa os 20 primeiros STUN da lista que o chiaki usa e redireciona no /etc/hosts
os que estiverem bloqueados/sem DNS para $TARGET_IP (stun.cloudflare.com).
  --all      redireciona os 20 sem testar
  --revert   remove o bloco do /etc/hosts
  --dry-run  mostra o que faria sem alterar nada
USAGE
}

TARGET_IP="162.159.207.0"
HOSTS_FILE="/etc/hosts"
MARK_BEGIN="# >>> chiaki-ng-remote-play-kit STUN"
MARK_END="# <<< chiaki-ng-remote-play-kit STUN"
STUN_PY="$REPO_ROOT/scripts/lib/stun.py"

ALL=0
REVERT=0
parse_common_flags "$@"
for a in "${REMAINING_ARGS[@]}"; do
  case "$a" in
    --all) ALL=1 ;;
    --revert) REVERT=1 ;;
    *) die "argumento desconhecido: $a (veja --help)" ;;
  esac
done

require_arch
need_cmd python3 || exit 2

# remove_block: escreve /etc/hosts sem o bloco do kit (via arquivo temporário + sudo install).
remove_block() {
  local tmp
  tmp="$(mktemp)"
  sed "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$HOSTS_FILE" >"$tmp"
  run_sudo install -m 0644 -o root -g root "$tmp" "$HOSTS_FILE"
  rm -f "$tmp"
}

has_block() { grep -qxF "$MARK_BEGIN" "$HOSTS_FILE"; }

flush_dns() { run_sudo resolvectl flush-caches 2>/dev/null || true; }

# ---- --revert ---------------------------------------------------------------------
if [[ "$REVERT" == "1" ]]; then
  if ! has_block; then
    log_ok "nada a reverter: nenhum bloco do kit em $HOSTS_FILE"
    exit 0
  fi
  backup_file "$HOSTS_FILE"
  remove_block
  flush_dns
  log_ok "bloco removido de $HOSTS_FILE"
  exit 0
fi

# ---- escolher hosts -----------------------------------------------------------------
mapfile -t candidates < <(python3 "$STUN_PY" list --count 20)
((${#candidates[@]} > 0)) || die "não obtive a lista de STUN"

to_redirect=()
if [[ "$ALL" == "1" ]]; then
  for hp in "${candidates[@]}"; do to_redirect+=("${hp%:*}"); done
  log_info "--all: redirecionando ${#to_redirect[@]} hosts sem testar"
else
  log_info "testando ${#candidates[@]} servidores STUN nesta rede (3s de timeout cada, em paralelo)..."
  # Testar pelos hostnames "puros" ignoraria um redirecionamento já existente; é o desejado:
  # se já estão redirecionados e respondendo, não há o que fazer.
  while read -r status hp _; do
    case "$status" in
      OK) printf '   %sOK%s        %s\n' "$C_GRN" "$C_OFF" "$hp" ;;
      *)
        printf '   %s%-9s%s %s\n' "$C_RED" "$status" "$C_OFF" "$hp"
        to_redirect+=("${hp%:*}")
        ;;
    esac
  done < <(python3 "$STUN_PY" test --timeout 3 "${candidates[@]}")
fi

if ((${#to_redirect[@]} == 0)); then
  log_ok "sua rede não precisa disto: todos os STUN respondem. Nada foi alterado."
  exit 0
fi

# ---- confirmar --------------------------------------------------------------------------
cat <<TXT

Vou adicionar ao $HOSTS_FILE, entre marcadores do kit, ${#to_redirect[@]} linha(s) do tipo:
   $TARGET_IP <host-stun-bloqueado>
Isso só muda como ESSES hostnames resolvem nesta máquina (todos passam a apontar para
stun.cloudflare.com). Nada mais é afetado. Reverter: $(basename "$0") --revert
TXT
confirm "Aplicar o redirecionamento?"

# ---- escrever (idempotente: remove bloco antigo, escreve o novo) -------------------------
backup_file "$HOSTS_FILE"
tmp_hosts="$(mktemp)"
trap 'rm -f "$tmp_hosts"' EXIT
sed "/^${MARK_BEGIN}$/,/^${MARK_END}$/d" "$HOSTS_FILE" >"$tmp_hosts"
{
  echo "$MARK_BEGIN"
  echo "# STUN bloqueados nesta rede -> stun.cloudflare.com. Gerado por 30-stun-redirect.sh em $(date +%F)."
  for h in "${to_redirect[@]}"; do echo "$TARGET_IP $h"; done
  echo "$MARK_END"
} >>"$tmp_hosts"
run_sudo install -m 0644 -o root -g root "$tmp_hosts" "$HOSTS_FILE"
flush_dns
log_ok "${#to_redirect[@]} host(s) redirecionado(s) em $HOSTS_FILE"

# ---- validar --------------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  log_info "[dry-run] validação pulada"
  exit 0
fi
log_info "validando: os hosts redirecionados devem responder rápido agora"
slow=0
while read -r status hp ms; do
  if [[ "$status" == "OK" && "$ms" -lt 100 ]]; then
    printf '   %sOK%s %4sms  %s\n' "$C_GRN" "$C_OFF" "$ms" "$hp"
  else
    printf '   %s%-9s%s %s\n' "$C_RED" "$status" "$C_OFF" "$hp"
    slow=1
  fi
done < <(python3 "$STUN_PY" test --timeout 3 "${to_redirect[@]/%/:3478}")
if ((slow)); then
  log_warn "algum host ainda não responde bem. Se o resolvedor não lê /etc/hosts, verifique /etc/nsswitch.conf (linha 'hosts:' deve conter 'files')."
  exit 1
fi
log_ok "pronto. Se o chiaki estava aberto, feche e abra de novo antes de conectar."
