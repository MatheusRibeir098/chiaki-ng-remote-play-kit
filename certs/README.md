# certs/

`comodo-rsa-dv-secure-server-ca.crt` — certificado **intermediário público** da COMODO/Sectigo:

- Subject: `CN=COMODO RSA Domain Validation Secure Server CA`
- Issuer: `CN=COMODO RSA Certification Authority` (root que já está no seu sistema)
- Validade: 2014-02-12 → 2029-02-11
- SHA-256 (DER): `02:AB:57:E4:E6:7A:0C:B4:8D:D2:FF:34:83:0E:8A:C4:0F:44:76:FB:08:CA:6B:E3:F5:CD:84:6F:64:68:40:F0`
- Origem oficial (AIA do certificado da Sony): http://crt.comodoca.com/COMODORSADomainValidationSecureServerCA.crt

Por que ele está aqui: o endpoint de push do PSN entrega só o certificado folha, sem esta
intermediária. Ver `docs/02-certificado-psn.md`. O script `10-install-ca-intermediate.sh`
prefere baixar da origem oficial e conferir o hash; este arquivo é o fallback offline.

Não é um segredo — é um certificado público, o mesmo que qualquer navegador baixa.
