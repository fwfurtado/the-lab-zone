---
tipo: adr
numero: 5
titulo: DNS split-horizon com PowerDNS (recursor na frente do authoritative)
status: aceito
fases: [3]
---

# ADR-0005 — DNS split-horizon com PowerDNS

## Status
Aceito (Fase 3).

## Contexto
Os serviços internos são expostos em `*.lab.the-lab.zone → 10.40.7.10` (IP privado do
Gateway). O Cloudflare hospeda só a zona pública (pro DNS-01 do ACME). Precisa resolver
interno sem quebrar a internet.

## Decisão
Split-horizon em um LXC (`10.40.1.53`): PowerDNS **Authoritative** serve `the-lab.zone`;
**Recursor na frente** resolve interno (forward pro auth) e externo (recursão raiz).
Recursor na :53 (LAN), auth em `127.0.0.1:5300`.

## Porquê
Auth não recursa; apontar a LAN só pra ele quebraria a internet (REFUSED, sem failover).
Recursão raiz é mais privada (queries direto aos autoritativos) e sem dependência de
terceiro — trocável por forward pra 1.1.1.1/Quad9 se quiser.

## Consequências
- Clientes da LAN apontam **só** pra `10.40.1.53` (sem secundário público).
- Recursor 5.x exige config YAML; o auth continua old-style (ver runbook gateway-dns).
- Wildcard catch-all é proibido (mascara NXDOMAIN com IP/cert errados).
