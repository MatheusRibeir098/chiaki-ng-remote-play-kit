# 02 — Certificado: a intermediária que a Sony não envia

**Em uma frase:** o servidor de push do PSN entrega só o certificado dele, sem a intermediária que o assina; a libcurl não completa cadeias sozinha, então a validação TLS falha e o chiaki trava antes de começar — a correção é instalar essa intermediária pública no trust store do sistema.

Script: `scripts/10-install-ca-intermediate.sh` · Atalho: `make install-ca`

## O que acontece

O chiaki-ng abre um WebSocket em `wss://<ip>-pushcl.np.communication.playstation.net/np/pushNotification` para receber as notificações que coordenam o holepunch. Esse servidor entrega **apenas o certificado folha**:

```
$ openssl s_client -connect <host>:443 -showcerts </dev/null
 0 s:CN=*.np.communication.playstation.net
   i:CN=COMODO RSA Domain Validation Secure Server CA
    Verify return code: 21 (unable to verify the first certificate)
```

Repare: só a profundidade `0`. Não há `1 s:CN=COMODO RSA Domain Validation Secure Server CA`. O root `COMODO RSA Certification Authority` **está** no seu sistema — o que falta é o elo do meio.

Navegadores resolvem isso buscando a intermediária pela extensão AIA do certificado. A libcurl (usada pelo chiaki) não faz isso. Resultado:

```
[E] websocket_thread_func: Connecting to push notification WebSocket ... failed with
    CURL error SSL peer certificate or SSH remote key was not OK
```

É um erro de configuração do lado da Sony. Reproduz em qualquer rede, em qualquer máquina Linux com libcurl.

## Por que variáveis de ambiente NÃO resolvem

A primeira ideia é dar um bundle próprio ao chiaki via `CURL_CA_BUNDLE`. Não funciona — essa variável é lida pelo **comando** `curl`, não pela **biblioteca** libcurl, que fixa o caminho em tempo de compilação (`--with-ca-bundle=/etc/ssl/certs/ca-certificates.crt`). Testamos direto na libcurl:

```python
import ctypes
c = ctypes.CDLL("libcurl.so.4")
h = c.curl_easy_init()
# CURLOPT_URL=10002, CURLOPT_NOBODY=44
c.curl_easy_setopt(h, 10002, b"https://<host>-pushcl.np.communication.playstation.net/")
c.curl_easy_setopt(h, 44, 1)
print(c.curl_easy_perform(h))   # -> 60 = SSL peer certificate ... not OK
```

Com `CURL_CA_BUNDLE`, `SSL_CERT_FILE` ou `SSL_CERT_DIR` apontando para um bundle que contém a intermediária: **continua 60**. A libcurl ignora as três. A única forma é o próprio trust store do sistema.

## A correção

```sh
sudo cp certs/comodo-rsa-dv-secure-server-ca.crt /etc/ca-certificates/trust-source/anchors/
sudo update-ca-trust
```

Depois disso `/etc/ssl/certs/ca-certificates.crt` (que é um link para `/etc/ca-certificates/extracted/tls-ca-bundle.pem`) passa a conter a intermediária, e o mesmo teste acima devolve `0`.

O script faz isso com verificações: baixa o certificado da origem oficial (AIA: `http://crt.comodoca.com/COMODORSADomainValidationSecureServerCA.crt`), confere o SHA-256, e só então instala. Se não conseguir baixar, usa a cópia em `certs/` — que tem o mesmo hash.

**Fingerprint SHA-256 esperado (DER):**
```
02:AB:57:E4:E6:7A:0C:B4:8D:D2:FF:34:83:0E:8A:C4:0F:44:76:FB:08:CA:6B:E3:F5:CD:84:6F:64:68:40:F0
```
Validade: 2014-02-12 → 2029-02-11. Emissor: `COMODO RSA Certification Authority`.

### ⚠️ Reinicie o chiaki depois

O chiaki tenta esse WebSocket **uma vez, na abertura**, e não repete. Uma instância que abriu antes da correção continua quebrada mesmo que você tente conectar de novo. Feche e abra.

## Segurança: o que muda de verdade

Adicionar um certificado ao trust store merece atenção. Aqui, honestamente:

- É uma **intermediária**, não um root. Ela já é assinada pelo root COMODO que está no seu sistema. Tudo o que ela pode assinar já era confiável por transitividade — você não está passando a confiar em nenhuma autoridade nova.
- A diferença prática: como âncora local, ela vale mesmo que a COMODO a revogue no futuro (a verificação de revogação da própria intermediária deixa de ocorrer). Risco baixo; ela expira em 2029 de qualquer jeito.
- É um certificado **público** — o mesmo que qualquer navegador baixa e usa em silêncio. Não é segredo, não é seu, não é da Sony.
- Se a Sony corrigir o servidor, você pode remover sem perder nada.

## Como saber se este é o seu caso

```sh
grep -h 'SSL peer certificate' ~/.local/share/Chiaki/Chiaki/log/*.log | tail -1
```
Se aparecer algo, é este. Ou, sem log: `make check` testa o endpoint e reporta `ssl=20` (falta emissor) vs `ssl=0` (ok).

## Como reverter

```sh
sudo rm /etc/ca-certificates/trust-source/anchors/comodo-rsa-dv-secure-server-ca.crt
sudo update-ca-trust
```
Ou `scripts/10-install-ca-intermediate.sh --revert`.
