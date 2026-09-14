#!/usr/bin/env bash
# 90-doctor.sh — lê o log de sessão mais recente do chiaki e diz o que deu errado
# (ou certo), em português, com o próximo passo. Somente leitura; não altera nada.
#
# Cada diagnóstico casa uma assinatura EXATA que apareceu em logs reais. A ordem
# importa: o primeiro que casar vence (um log pode ter várias marcas).

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--log <arquivo>] [--json] [--help]

  --log <arquivo>  analisa este log em vez do mais recente em
                   ~/.local/share/Chiaki/Chiaki/log/
  --json           saída em JSON (uma linha) para automação
USAGE
}

log_file=""
json=0
parse_common_flags "$@"
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --log)
      [[ -n "${2:-}" ]] || die "--log espera um arquivo"
      log_file="$2"
      shift 2
      ;;
    --json)
      json=1
      shift
      ;;
    *) die "argumento desconhecido: $1 (veja --help)" ;;
  esac
done

[[ -n "$log_file" ]] || log_file="$(newest_chiaki_log)"
[[ -n "$log_file" && -r "$log_file" ]] || die "nenhum log do chiaki encontrado. Abra o chiaki e tente conectar uma vez; ou passe --log <arquivo>."

# ---- estado do sistema (independe do log) ----------------------------------
pkg_version="$(pacman -Q chiaki-ng-git 2>/dev/null | awk '{print $2}' || true)"
[[ -n "$pkg_version" ]] || pkg_version="$(pacman -Q chiaki-ng 2>/dev/null | awk '{print "chiaki-ng(AUR) " $2}' || true)"
[[ -n "$pkg_version" ]] || pkg_version="não instalado"
binary_fix="não"
# process substitution: com pipefail, `strings | grep -q` falharia por SIGPIPE ao casar cedo
if [[ -x /usr/bin/chiaki ]] && command -v strings >/dev/null 2>&1 &&
  grep -qF 'contains %zu extra byte' <(strings /usr/bin/chiaki 2>/dev/null); then
  binary_fix="sim"
fi
ca_anchor="não"
[[ -f /etc/ca-certificates/trust-source/anchors/comodo-rsa-dv-secure-server-ca.crt ]] && ca_anchor="sim"

# ---- classificação ---------------------------------------------------------
has() { grep -qE -- "$1" "$log_file"; }
count() { grep -cE -- "$1" "$log_file" || true; }

code=""
title=""
cause=""
action=""

# Precedência:
#   1. sucesso (streaminfo) vence qualquer erro anterior — um PIN errado antes de acertar não importa;
#   2. entre as falhas, vence a que aparece POR ÚLTIMO no log (é o que travou de fato);
#   3. "Canceling ... over PSN" só quando não há outra causa — é consequência, não causa;
#   4. senão, desconhecido.
last_line_of() { grep -nE -- "$1" "$log_file" | tail -1 | cut -d: -f1 || true; }

if has 'StreamConnection successfully received streaminfo'; then
  code="ok"
else
  best=0
  for sig in \
    'ssl_cert|websocket_thread_func: .*failed with CURL error SSL peer certificate' \
    'customdata1|Failed to decode "customData1"' \
    'pin_incorrect|Ctrl received Login message: PIN incorrect' \
    'console_no_join|Timed out waiting for holepunch session start notifications' \
    'ctrl_no_response|Failed to receive session request response' \
    'senkusha|Senkusha Takion connect failed'; do
    n="$(last_line_of "${sig#*|}")"
    if [[ -n "$n" && "$n" -gt "$best" ]]; then
      best="$n"
      code="${sig%%|*}"
    fi
  done
  if [[ -z "$code" ]]; then
    if has 'Canceling establishing connection over PSN'; then code="stuck_cancel"; else code="unknown"; fi
  fi
fi

case "$code" in
  ok)
    when="$(grep -E 'StreamConnection successfully received streaminfo' "$log_file" | tail -1 | grep -oE '[0-9]{2}:[0-9]{2}:[0-9]{2}' | head -1)"
    quality="$(grep -E 'received connection quality' "$log_file" | tail -1 | grep -oE 'target_bitrate=[0-9]+|rtt=[0-9]+([,.][0-9]+)?' | paste -sd' ' || true)"
    title="Conectado — streaming ativo${when:+ às $when}"
    cause="Todas as etapas passaram: PSN, holepunch, controle, PIN e vídeo."
    action="Nada a fazer.${quality:+ Última medição: $quality}"
    ;;
  ssl_cert)
    title="Certificado da PSN não valida (SSL)"
    cause="O servidor de push da Sony entrega só o certificado folha, sem a intermediária COMODO. A libcurl não consegue completar a cadeia e a conexão via PSN nem começa."
    action="make install-ca   (instala a intermediária no trust store; depois reabra o chiaki — ele só tenta esse WebSocket ao iniciar)"
    ;;
  customdata1)
    title="Binário do chiaki sem o fix do customData1 (PS5 Pro)"
    cause="Seu console devolve um customData1 de 17 bytes; versões antigas exigem 16 e abortam a sessão (streetpea/chiaki-ng#810). O pacote chiaki-ng do AUR está nesse caso apesar do número de versão."
    action="make build   (instala o chiaki-ng em um commit com o fix)"
    ;;
  pin_incorrect)
    title="PIN de login incorreto ($(count 'PIN incorrect') tentativa(s))"
    cause="O console pede o passcode de 4 dígitos do SEU PERFIL no PS5 (o que você digita ao entrar na conta no console). Não é a senha da PSN nem o PIN de registro do Remote Play."
    action="Digite o passcode correto. Se não lembrar, confira no PS5: Ajustes → Usuários e Contas → Informações de Login → Código de Acesso. Evite chutar: muitas tentativas erradas bloqueiam o login temporariamente."
    ;;
  console_no_join)
    title="Console não entrou na sessão em 30 s"
    cause="A PSN aceitou o pedido, mas o PS5 não respondeu a tempo. Quase sempre é o console em repouso acordando: a 1ª tentativa só o acorda."
    action="Tente conectar de novo agora (a 2ª/3ª costuma entrar). Se persistir, no PS5: Ajustes → Sistema → Economia de energia → Recursos disponíveis no modo de repouso → ligue 'Permanecer conectado à internet' e 'Ativar ligar o PS5 pela rede'."
    ;;
  ctrl_no_response)
    title="Console conectou, mas não respondeu ao pedido de sessão"
    cause="O canal de controle abriu, porém o PS5 devolveu mensagens erradas 3 vezes ('Expected CTRL MESSAGE') e desistiu. Acontece quando o console ainda está terminando de acordar do repouso ou fechando a sessão anterior."
    action="Espere ~10 s e tente de novo. Se repetir várias vezes com o console ligado, reinicie o chiaki."
    ;;
  senkusha)
    stun_fail="$(count 'Failed to get external address from stun\.')"
    if has 'Conexão recusada|Connection refused' && [[ "$stun_fail" -ge 3 ]]; then
      code="stun_blocked"
      title="Vídeo recusado após ${stun_fail} servidores STUN bloqueados"
      cause="Sua rede bloqueia os servidores STUN da lista que o chiaki baixa. Cada um gasta ~5 s até desistir; a fase de vídeo atrasa tanto que o console fecha o socket e o pacote chega 'recusado'. O controle conecta, o vídeo não."
      action="make stun   (redireciona só os STUN bloqueados na SUA rede para um que responda; reabra o chiaki e tente de novo)"
    else
      code="udp_blocked"
      title="Canal de vídeo (UDP P2P) não estabelece"
      cause="O controle conectou, mas a rede não deixa o fluxo UDP direto do vídeo passar. Isso é firewall da rede, não do seu PC."
      action="Tente por outra rede (hotspot do celular é o teste definitivo). Se funcionar lá, o bloqueio é da rede atual."
    fi
    ;;
  stuck_cancel)
    title="Travado em 'Cancelling connection over PSN'"
    cause="Versões antigas do chiaki-ng ficam presas no cancelamento quando a conexão via PSN falha (em geral após o erro de SSL). O processo só sai com kill -9."
    action="pkill -9 -x chiaki; depois: make install-ca && make build"
    ;;
  unknown)
    title="Nenhuma assinatura conhecida"
    cause="O log não tem nenhum dos padrões catalogados. Veja as últimas linhas relevantes abaixo (dados sensíveis mascarados)."
    action="Abra uma issue no kit com o trecho abaixo, ou compare com docs/06-troubleshooting.md."
    ;;
esac

# ---- saída -----------------------------------------------------------------
if [[ "$json" == "1" ]]; then
  python3 - "$code" "$title" "$cause" "$action" "$log_file" "$pkg_version" "$binary_fix" "$ca_anchor" <<'PY'
import json, sys
k = ["code","title","cause","action","log","package","binary_has_fix","ca_anchor"]
print(json.dumps(dict(zip(k, sys.argv[1:])), ensure_ascii=False))
PY
  exit 0
fi

echo "log analisado : $log_file"
echo "pacote        : $pkg_version"
echo "binário c/ fix: $binary_fix"
echo "anchor CA     : $ca_anchor"
echo
if [[ "$code" == "ok" ]]; then
  printf '%s[ ok ]%s %s\n' "$C_GRN" "$C_OFF" "$title"
else
  printf '%s[warn]%s %s\n' "$C_YLW" "$C_OFF" "$title"
fi
printf '\n  %sCAUSA%s  %s\n' "$C_DIM" "$C_OFF" "$cause"
printf '  %sFAZER%s  %s\n' "$C_DIM" "$C_OFF" "$action"

if [[ "$code" == "unknown" ]]; then
  echo
  echo "--- últimas linhas relevantes (mascaradas) ---"
  grep -vE 'libplacebo|VK_FORMAT|VK_COLOR|Heartbeat|swapchain|PING|seq num|data ack|P frame' "$log_file" |
    tail -15 |
    sed -E 's/([0-9]{1,3}\.){3}[0-9]{1,3}/<ip>/g; s/([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}/<mac>/g; s/[0-9a-fA-F]{24,}/<hex>/g; s/(login pin +)"[^"]*"/\1"<pin>"/g'
fi
