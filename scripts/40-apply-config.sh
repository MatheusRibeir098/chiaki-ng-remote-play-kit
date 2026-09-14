#!/usr/bin/env bash
# 40-apply-config.sh — aplica config/Chiaki.conf.example em ~/.config/Chiaki/Chiaki.conf
# SEM tocar em segredos.
#
# Regras:
#   - Config não existe  -> copia o template inteiro.
#   - Config já existe   -> só adiciona, em [settings], as chaves do template que
#                           ainda não existem. Nunca sobrescreve valores. Preserva
#                           [registered_hosts], [manual_hosts], tokens PSN etc.
#   - Recusa rodar com o chiaki aberto: ele reescreve a config ao sair e desfaria tudo.
#
# O formato é QSettings (INI do Qt): chaves com '\' e valores como @Rect(...).
# configparser do Python estraga isso, por isso o merge é linha a linha.

# shellcheck source=scripts/lib/common.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

usage() {
  cat <<USAGE
uso: $(basename "$0") [--verbose-log on|off] [--dry-run] [--help]

  --verbose-log on|off   força log_verbose (diagnóstico). Default do template: off.
USAGE
}

TEMPLATE="$REPO_ROOT/config/Chiaki.conf.example"
TARGET="$HOME/.config/Chiaki/Chiaki.conf"
verbose_log=""

parse_common_flags "$@"
set -- "${REMAINING_ARGS[@]+"${REMAINING_ARGS[@]}"}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --verbose-log)
      [[ "${2:-}" =~ ^(on|off)$ ]] || die "--verbose-log espera 'on' ou 'off'"
      verbose_log="$2"
      shift 2
      ;;
    *) die "argumento desconhecido: $1 (veja --help)" ;;
  esac
done

need_cmd python3 || exit 2
[[ -f "$TEMPLATE" ]] || die "template não encontrado: $TEMPLATE"

if pgrep -x chiaki >/dev/null 2>&1; then
  die "O chiaki está aberto. Feche-o antes: ele reescreve a config ao sair e desfaria esta alteração."
fi

mkdir -p "$(dirname "$TARGET")"

if [[ ! -f "$TARGET" ]]; then
  log_info "Config não existe; copiando o template para $TARGET"
  run cp "$TEMPLATE" "$TARGET"
else
  log_info "Config existente; adicionando só as chaves de [settings] que faltam (sem sobrescrever)."
  # backup_file usa sudo por padrão (arquivos do sistema); aqui é do usuário.
  bkp="${TARGET}.bak-chiaki-kit-$(date +%Y%m%d-%H%M%S)"
  run cp -a "$TARGET" "$bkp"
  log_info "backup: $bkp"
fi

# Merge idempotente. Em dry-run só relata.
DRY_RUN="$DRY_RUN" VERBOSE_LOG="$verbose_log" python3 - "$TEMPLATE" "$TARGET" <<'PY'
import os, re, sys

template, target = sys.argv[1], sys.argv[2]
dry = os.environ.get("DRY_RUN") == "1"
force_verbose = os.environ.get("VERBOSE_LOG", "")

def parse_settings_keys(path):
    """Devolve {chave: valor} da seção [settings] (ignora comentários ; e #)."""
    out, sec = {}, None
    for line in open(path, encoding="utf-8"):
        s = line.strip()
        if not s or s[0] in ";#":
            continue
        if s.startswith("[") and s.endswith("]"):
            sec = s[1:-1]; continue
        if sec == "settings" and "=" in s:
            k, v = s.split("=", 1)
            out[k.strip()] = v.strip()
    return out

wanted = parse_settings_keys(template)
if force_verbose:
    wanted["log_verbose"] = "true" if force_verbose == "on" else "false"

text = open(target, encoding="utf-8").read() if os.path.exists(target) else ""
lines = text.splitlines()

# Localiza a seção [settings]; cria no fim se não houver.
start = next((i for i, l in enumerate(lines) if l.strip() == "[settings]"), None)
if start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.append("[settings]")
    start = len(lines) - 1
end = next((i for i in range(start + 1, len(lines)) if lines[i].strip().startswith("[")), len(lines))

existing = {}
for i in range(start + 1, end):
    s = lines[i].strip()
    if s and s[0] not in ";#" and "=" in s:
        existing[s.split("=", 1)[0].strip()] = i

added, changed = [], []
for k, v in wanted.items():
    if k in existing:
        # Só log_verbose forçado por flag pode alterar um valor existente.
        if k == "log_verbose" and force_verbose:
            cur = lines[existing[k]].split("=", 1)[1].strip()
            if cur != v:
                lines[existing[k]] = f"{k}={v}"; changed.append(k)
        continue
    lines.insert(end, f"{k}={v}"); end += 1; added.append(k)

if not added and not changed:
    print("[ ok ] nada a alterar: todas as chaves já presentes.")
    sys.exit(0)

msg = []
if added:   msg.append("adicionadas: " + ", ".join(added))
if changed: msg.append("alteradas: " + ", ".join(changed))
if dry:
    print("[dry-run] " + "; ".join(msg))
    sys.exit(0)
open(target, "w", encoding="utf-8").write("\n".join(lines) + "\n")
print("[ ok ] " + "; ".join(msg))
PY

# Se o log_verbose foi pedido no caminho "arquivo novo", o template já tem
# log_verbose=false e o python acima ajustou. Nada mais a fazer.
[[ "$DRY_RUN" == "1" ]] || log_ok "Config aplicada em $TARGET (segredos preservados)."
