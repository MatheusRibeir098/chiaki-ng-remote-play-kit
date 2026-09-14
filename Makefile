# Atalhos para o kit. Cada alvo chama um script em scripts/; todos aceitam DRY_RUN=1.
SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: help check install-ca build stun config doctor install revert lint

help: ## Lista os alvos
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

check: ## 1) Diagnostica ambiente e rede ANTES de mudar qualquer coisa
	@scripts/00-check-env.sh

install-ca: ## 2) Instala a intermediária COMODO que o endpoint PSN não envia
	@scripts/10-install-ca-intermediate.sh

build: ## 3) Compila e instala o chiaki-ng no commit que tem o fix do PS5 Pro
	@scripts/20-build-chiaki-ng.sh

stun: ## 4) (opcional) Redireciona só os STUN que a SUA rede bloqueia
	@scripts/30-stun-redirect.sh

config: ## 5) Aplica o template de config sem tocar em segredos existentes
	@scripts/40-apply-config.sh

doctor: ## Lê o último log do chiaki e diz qual é o problema
	@scripts/90-doctor.sh

install: check install-ca build config ## Faz 1→3 e 5 (o STUN só se o check indicar)
	@echo; echo "Instalação concluída. Se o 'check' apontou STUN bloqueado, rode: make stun"

revert: ## Desfaz tudo que o kit alterou no sistema
	@scripts/10-install-ca-intermediate.sh --revert
	@scripts/30-stun-redirect.sh --revert
	@echo "Para remover o pacote: sudo pacman -R chiaki-ng-git"

lint: ## shellcheck + shfmt nos scripts
	@shellcheck -x -P SCRIPTDIR scripts/*.sh scripts/lib/*.sh
	@shfmt -d -i 2 -ci scripts/
