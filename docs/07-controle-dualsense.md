# 07 — Controle DualSense por Bluetooth

**Em uma frase:** o DualSense guarda **um único vínculo Bluetooth por vez**; se você o usou no PS5 por Bluetooth, o vínculo com o PC morre e o controle "conecta" mas não funciona — a solução é apagar o registro e parear de novo.

## O sintoma

- No `bluetoothctl`, o controle aparece **Connected: yes**, mas nenhum jogo/app reage.
- Não existe dispositivo de entrada (`/proc/bus/input/devices` sem "DualSense") e o módulo `hid_playstation` não carrega.
- No log do BlueZ aparece a causa:

```
bluetoothd: profiles/input/device.c:hidp_add_connection() Rejected connection from !bonded device /org/bluez/hci0/dev_XX_XX_XX_XX_XX_XX
```

`!bonded` = o BlueZ não tem a **link key** desse controle. Confirme (precisa de sudo):

```sh
sudo grep -q '^\[LinkKey\]' /var/lib/bluetooth/*/XX:XX:XX:XX:XX:XX/info && echo "vínculo ok" || echo "SEM link key"
```

Marcar como confiável (`bluetoothctl trust`) **não resolve** sozinho — sem link key continua rejeitado.

## A correção (1 minuto)

```sh
MAC=XX:XX:XX:XX:XX:XX          # veja em: bluetoothctl devices
bluetoothctl remove $MAC        # apaga o registro incompleto
```

Coloque o controle em **modo de pareamento**: com ele desligado, segure **Create + PS** por ~5 s até a barra de luz **piscar rápido**. Então:

```sh
bluetoothctl scan on            # aguarde o controle aparecer, depois Ctrl+C
bluetoothctl pair $MAC
bluetoothctl trust $MAC
bluetoothctl connect $MAC
```

## Como saber que deu certo

```sh
bluetoothctl info $MAC | grep -E 'Paired|Bonded|Trusted|Connected'   # tudo "yes"
lsmod | grep hid_playstation                                          # carregado
grep 'DualSense' /proc/bus/input/devices                              # controle, sensores e touchpad
```

O chiaki-ng detecta o controle sozinho (SDL com hot-plug). No log da próxima sessão aparece `Enabling DualSense features`.

## Vibração e gatilhos adaptativos

Precisam de acesso ao `/dev/hidraw*` do controle. Se você tem o **Steam** instalado, a regra `60-steam-input.rules` já concede isso (`TAG+="uaccess"` para `054C:0CE6` via Bluetooth e USB). Sem Steam, instale `game-devices-udev` do AUR. Confira:

```sh
for h in /sys/class/hidraw/hidraw*; do grep -q 'DualSense' "$h/device/uevent" && getfacl -p "/dev/$(basename "$h")" | grep '^user:'; done
```

Deve listar o seu usuário com `rw-`.

## Para não acontecer de novo

Use o controle no PS5 **por cabo USB** quando estiver em casa — USB não mexe no vínculo Bluetooth. Se usar por Bluetooth no console, o vínculo com o PC vai quebrar e você refaz a receita acima.

## Como reverter

Nada a reverter — o pareamento é o mesmo que qualquer sistema faz. Para esquecer o controle: `bluetoothctl remove $MAC`.
