#!/usr/bin/env bash
# 10-install-ca-intermediate.sh — instala no trust store do sistema a intermediária
# "COMODO RSA Domain Validation Secure Server CA".
#
# Por quê: o endpoint de push do PSN (*.np.communication.playstation.net) entrega só o
# certificado folha, sem a intermediária. Navegadores buscam a cadeia faltante sozinhos;
# a libcurl (usada pelo chiaki) não — e ignora CURL_CA_BUNDLE/SSL_CERT_FILE. Sem isto, o
# chiaki trava em "Cancelling connection with console over PSN". Ver docs/02-certificado-psn.md.
#
# Segurança: a fingerprint SHA-256 do certificado é conferida contra um valor fixo antes
# de qualquer instalação. É um certificado público que já encadeia num root do seu sistema.

source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--dry-run] [--revert] [--help]

Instala a intermediária COMODO em $ANCHOR_PATH e roda update-ca-trust.
  --revert   remove a âncora e roda update-ca-trust
  --dry-run  mostra o que faria sem alterar nada
USAGE
}

ANCHOR_PATH="/etc/ca-certificates/trust-source/anchors/comodo-rsa-dv-secure-server-ca.crt"
AIA_URL="http://crt.comodoca.com/COMODORSADomainValidationSecureServerCA.crt"
FALLBACK_PEM="$REPO_ROOT/certs/comodo-rsa-dv-secure-server-ca.crt"
EXPECTED_FP="02:AB:57:E4:E6:7A:0C:B4:8D:D2:FF:34:83:0E:8A:C4:0F:44:76:FB:08:CA:6B:E3:F5:CD:84:6F:64:68:40:F0"
EXPECTED_SUBJECT_CN="COMODO RSA Domain Validation Secure Server CA"
EXPECTED_ISSUER_CN="COMODO RSA Certification Authority"
PSN_PUSH_HOST="44-232-96-0-pushcl.np.communication.playstation.net"

REVERT=0
parse_common_flags "$@"
for a in "${REMAINING_ARGS[@]}"; do
  case "$a" in
    --revert) REVERT=1 ;;
    *) die "argumento desconhecido: $a (veja --help)" ;;
  esac
done

require_arch
need_cmd openssl update-ca-trust || exit 2

fingerprint_of() { openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null | sed 's/^.*=//'; }
cn_of() { openssl x509 -in "$1" -noout "$2" 2>/dev/null | sed -E 's/.*CN *= *([^,]+).*/\1/'; }

# ---- --revert ---------------------------------------------------------------------
if [[ "$REVERT" == "1" ]]; then
  if [[ ! -f "$ANCHOR_PATH" ]]; then
    log_ok "nada a reverter: $ANCHOR_PATH não existe"
    exit 0
  fi
  run_sudo rm -f "$ANCHOR_PATH"
  run_sudo update-ca-trust
  log_ok "âncora removida e trust store regenerado"
  exit 0
fi

# ---- já instalado? ----------------------------------------------------------------
if [[ -f "$ANCHOR_PATH" ]] && [[ "$(fingerprint_of "$ANCHOR_PATH")" == "$EXPECTED_FP" ]]; then
  log_ok "intermediária já instalada em $ANCHOR_PATH (fingerprint confere)"
  exit 0
fi

# ---- obter o certificado ------------------------------------------------------------
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
pem="$tmp/intermediate.pem"

log_info "baixando a intermediária da origem oficial (AIA): $AIA_URL"
if timeout 20 curl -fsSL "$AIA_URL" -o "$tmp/intermediate.der" 2>/dev/null &&
  openssl x509 -inform DER -in "$tmp/intermediate.der" -out "$pem" 2>/dev/null; then
  log_ok "download ok"
else
  log_warn "download falhou; usando a cópia do repositório: $FALLBACK_PEM"
  [[ -f "$FALLBACK_PEM" ]] || die "cópia local ausente: $FALLBACK_PEM"
  cp "$FALLBACK_PEM" "$pem"
fi

# ---- verificar identidade -----------------------------------------------------------
fp="$(fingerprint_of "$pem")"
[[ "$fp" == "$EXPECTED_FP" ]] || die "fingerprint NÃO confere. esperado $EXPECTED_FP, obtido ${fp:-<vazio>}. Abortando."
[[ "$(cn_of "$pem" -subject)" == "$EXPECTED_SUBJECT_CN" ]] || die "subject inesperado: $(cn_of "$pem" -subject)"
[[ "$(cn_of "$pem" -issuer)" == "$EXPECTED_ISSUER_CN" ]] || die "issuer inesperado: $(cn_of "$pem" -issuer)"
log_ok "certificado verificado: CN=$EXPECTED_SUBJECT_CN, fingerprint confere"

# ---- explicar e confirmar --------------------------------------------------------------
cat <<TXT

O que vai acontecer:
  1. Copiar a intermediária pública da COMODO para $ANCHOR_PATH
  2. Rodar update-ca-trust para regenerar /etc/ssl/certs/ca-certificates.crt
  3. Testar o TLS do endpoint de push do PSN

Risco: baixo. É um certificado intermediário público que já encadeia num root presente
no seu sistema — não amplia a confiança para nada novo. Reverter: $(basename "$0") --revert
TXT
confirm "Instalar a âncora?"

# ---- instalar ---------------------------------------------------------------------------
run_sudo install -m 0644 "$pem" "$ANCHOR_PATH"
run_sudo update-ca-trust
log_ok "âncora instalada e trust store regenerado"

# ---- validar ------------------------------------------------------------------------------
if [[ "$DRY_RUN" == "1" ]]; then
  log_info "[dry-run] validação pulada"
  exit 0
fi
rc="$(timeout 15 curl -sS -o /dev/null -w '%{ssl_verify_result}' "https://$PSN_PUSH_HOST/" 2>/dev/null || echo net)"
case "$rc" in
  0) log_ok "TLS do endpoint PSN valida agora (ssl_verify_result=0)" ;;
  net) log_warn "instalado, mas não consegui alcançar o endpoint para validar (rede)" ;;
  *)
    log_err "instalado, mas o TLS ainda falha (ssl_verify_result=$rc). Reinicie o chiaki e rode 00-check-env.sh"
    exit 1
    ;;
esac
log_info "IMPORTANTE: se o chiaki estava aberto, feche e abra de novo — ele só tenta esse WebSocket ao iniciar."
