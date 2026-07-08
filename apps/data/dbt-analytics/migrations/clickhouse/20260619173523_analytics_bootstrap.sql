-- NO-OP desde a migração do RBAC do `analytics` pro operator.
-- Ver docs/runbooks/argo-workflows/workflows-elt-clickhouse-dbt.md
--
-- ANTES esta migration criava o usuário por SQL:
--   CREATE USER IF NOT EXISTS analytics IDENTIFIED WITH sha256_password ...
--   GRANT SELECT ON `default`.* / GRANT ALL ON analytics.* / GRANT SELECT ON system.*
--
-- POR QUE SAIU:
--   1. `IF NOT EXISTS` é idempotente na EXISTÊNCIA, não no ESTADO: rotacionar a senha
--      no 1Password nunca reaplicava (e o goose não re-roda migration já aplicada).
--   2. Usuário criado por SQL mora no access storage do ClickHouse (system.users
--      storage='disk'), enquanto `analytics.goose_db_version` é DADO (PVC). Ciclos de
--      vida distintos: o usuário sumiu num recreate, o registro do goose sobreviveu, o
--      goose reportou "no migrations to run" e o dbt quebrou com AUTHENTICATION_FAILED.
--
-- AGORA usuário + rede + grants são declarativos no ClickHouseInstallation
--   (apps/data/clickhouse/manifests/clickhouse-instalation.yaml -> files."users.d/custom-users.xml"),
--   com hash SHA256 vindo do ESO. O operator reconcilia a cada boot.
--
-- O arquivo PERMANECE: a versão já está em goose_db_version e o goose não re-roda
-- migrations aplicadas — removê-lo criaria drift. Corpo neutralizado porque o ClickHouse
-- PROÍBE gerenciar a mesma entidade de acesso por XML e por SQL ao mesmo tempo: recriar
-- o usuário aqui quebraria o bootstrap de um cluster novo (DR).

-- +goose Up
-- +goose StatementBegin
SELECT 1;
-- +goose StatementEnd

-- +goose Down
-- +goose StatementBegin
SELECT 1;
-- +goose StatementEnd
