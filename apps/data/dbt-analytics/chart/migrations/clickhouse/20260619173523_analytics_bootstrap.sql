-- Bootstrap do RBAC do analytics. O database é criado pelo step `ensure-db` do Workflow
-- (o CHI da Altinity não cria database declarativamente; e a tabela de versão do goose
-- precisa de um db que já exista). Aqui versionamos user + grants.
--
-- ISOLAMENTO: SELECT em default.* (schema do Langfuse, read-only) + ALL em analytics.* +
-- SELECT em system.* (introspecção do dbt). Nenhuma escrita em default.
--
-- A senha vem do env ANALYTICS_PASSWORD (secret clickhouse-analytics) via envsub — sem
-- hardcode. Roda UMA vez (versionado); rotação = nova migration ou ALTER USER manual.

-- +goose Up
-- +goose envsub on
-- +goose StatementBegin
CREATE USER IF NOT EXISTS analytics
  IDENTIFIED WITH sha256_password BY '${ANALYTICS_PASSWORD}'
  HOST IP '10.245.0.0/16', IP '127.0.0.1', IP '::1';
-- +goose StatementEnd
-- +goose StatementBegin
GRANT SELECT ON `default`.* TO analytics;
-- +goose StatementEnd
-- +goose StatementBegin
GRANT ALL ON analytics.* TO analytics;
-- +goose StatementEnd
-- +goose StatementBegin
GRANT SELECT ON system.* TO analytics;
-- +goose StatementEnd
-- +goose envsub off

-- +goose Down
-- +goose StatementBegin
DROP USER IF EXISTS analytics;
-- +goose StatementEnd
