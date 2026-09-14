# 99 — Reverter tudo

**Em uma frase:** o kit altera três coisas no sistema (uma âncora de CA, um pacote, um bloco no `/etc/hosts`) e uma no seu perfil (`Chiaki.conf`); cada uma tem backup e um comando de volta, e `make revert` desfaz as do sistema de uma vez.

## Atalho

```sh
make revert
```
Executa, nesta ordem: `10-install-ca-intermediate.sh --revert`, `30-stun-redirect.sh --revert`, e mostra o comando para remover o pacote (esse pede confirmação sua).

## Manualmente, na ordem inversa da instalação

### 1. STUN no `/etc/hosts` (`30-stun-redirect.sh`)
```sh
sudo sed -i '/# >>> chiaki-ng-remote-play-kit STUN/,/# <<< chiaki-ng-remote-play-kit STUN/d' /etc/hosts
sudo resolvectl flush-caches 2>/dev/null || true
```
Backup: `/etc/hosts.bak-chiaki-kit-<data>`. Para restaurar o arquivo inteiro: `sudo cp /etc/hosts.bak-chiaki-kit-<data> /etc/hosts`.

### 2. Pacote (`20-build-chiaki-ng.sh`)
```sh
sudo pacman -R chiaki-ng-git
```
Não há arquivos residuais além dos que o pacote instalou. Sua config em `~/.config/Chiaki/` fica.

### 3. Certificado intermediário (`10-install-ca-intermediate.sh`)
```sh
sudo rm -f /etc/ca-certificates/trust-source/anchors/comodo-rsa-dv-secure-server-ca.crt
sudo update-ca-trust
```
Confirme: `grep -c 'BEGIN CERTIFICATE' /etc/ca-certificates/extracted/tls-ca-bundle.pem` deve voltar ao número anterior (121 na máquina de referência; o seu pode diferir).

### 4. Config do chiaki (`40-apply-config.sh`)
O script só adiciona chaves não sensíveis em `[settings]` e cria `~/.config/Chiaki/Chiaki.conf.bak-chiaki-kit-<data>` antes. Para voltar:
```sh
cp ~/.config/Chiaki/Chiaki.conf.bak-chiaki-kit-<data> ~/.config/Chiaki/Chiaki.conf
```
(com o chiaki fechado — ele reescreve o arquivo ao sair). Suas chaves `psn_*`, `[registered_hosts]` e `[manual_hosts]` nunca são tocadas pelo kit.

## Onde ficam os backups

| Arquivo | Backup |
|---|---|
| `/etc/hosts` | `/etc/hosts.bak-chiaki-kit-<data>` |
| `~/.config/Chiaki/Chiaki.conf` | `~/.config/Chiaki/Chiaki.conf.bak-chiaki-kit-<data>` |
| trust store | não precisa — remover o arquivo e rodar `update-ca-trust` regenera |

Os `.bak` não são apagados automaticamente. Quando estiver satisfeito, pode removê-los.

## Como saber se está tudo revertido

```sh
ls /etc/ca-certificates/trust-source/anchors/ | grep -c comodo   # 0
grep -c 'chiaki-ng-remote-play-kit STUN' /etc/hosts                                # 0
pacman -Q chiaki-ng-git 2>&1 | grep -c 'não foi encontrado\|was not found'  # 1
```

## Como reverter

Este é o documento de reversão. Para refazer a instalação: `make install`.
