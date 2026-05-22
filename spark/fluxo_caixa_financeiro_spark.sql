WITH
se1_receber_base AS (
  SELECT
    mdmTenantId,
    company_group,
    TRIM(E1_FILIAL) AS filial,
    TRIM(E1_PREFIXO) AS prefixo,
    TRIM(E1_NUM) AS numero,
    TRIM(E1_PARCELA) AS parcela,
    to_date(TRIM(E1_VENCTO), 'yyyyMMdd') AS data_vencimento,
    to_date(NULLIF(TRIM(E1_BAIXA), ''), 'yyyyMMdd') AS data_baixa,
    to_date(NULLIF(TRIM(E1_VENCREA), ''), 'yyyyMMdd') AS data_vencimento_real,
    CAST(TRIM(E1_VALOR) AS DECIMAL(18, 2)) AS valor_original,
    CAST(TRIM(E1_SALDO) AS DECIMAL(18, 2)) AS saldo_aberto,
    TRIM(E1_CLIENTE) AS cod_parceiro,
    TRIM(E1_LOJA) AS loja_parceiro,
    TRIM(E1_TIPO) AS tipo_titulo,
    protheus_pk,
    mdmDeleted,
    mdmCounterForEntity,
    _ingestionDatetime,
    ROW_NUMBER() OVER (
      PARTITION BY mdmTenantId, protheus_pk
      ORDER BY _ingestionDatetime DESC, mdmCounterForEntity DESC
    ) AS ranking
  FROM ingestion_stg_protheus_carol_se1
  WHERE TRIM(Deleted) = 'false'
),

se2_pagar_base AS (
  SELECT
    mdmTenantId,
    company_group,
    TRIM(E2_FILIAL) AS filial,
    TRIM(E2_PREFIXO) AS prefixo,
    TRIM(E2_NUM) AS numero,
    TRIM(E2_PARCELA) AS parcela,
    to_date(TRIM(E2_VENCTO), 'yyyyMMdd') AS data_vencimento,
    to_date(NULLIF(TRIM(E2_BAIXA), ''), 'yyyyMMdd') AS data_baixa,
    to_date(NULLIF(TRIM(E2_VENCREA), ''), 'yyyyMMdd') AS data_vencimento_real,
    CAST(TRIM(E2_VALOR) AS DECIMAL(18, 2)) AS valor_original,
    CAST(TRIM(E2_SALDO) AS DECIMAL(18, 2)) AS saldo_aberto,
    TRIM(E2_FORNECE) AS cod_parceiro,
    TRIM(E2_LOJA) AS loja_parceiro,
    TRIM(E2_TIPO) AS tipo_titulo,
    protheus_pk,
    mdmDeleted,
    mdmCounterForEntity,
    _ingestionDatetime,
    ROW_NUMBER() OVER (
      PARTITION BY mdmTenantId, protheus_pk
      ORDER BY _ingestionDatetime DESC, mdmCounterForEntity DESC
    ) AS ranking
  FROM ingestion_stg_protheus_carol_se2
  WHERE TRIM(Deleted) = 'false'
),

entradas_caixa AS (
  SELECT
    'ENTRADA' AS tipo_fluxo,
    se1.mdmTenantId,
    se1.company_group,
    se1.filial,
    COALESCE(se1.data_baixa, se1.data_vencimento_real, se1.data_vencimento) AS data_movimento,
    se1.prefixo,
    se1.numero,
    se1.parcela,
    CONCAT(se1.prefixo, '-', se1.numero, '-', se1.parcela) AS titulo_identificacao,
    se1.valor_original AS valor_movimento,
    CASE
      WHEN se1.data_baixa IS NOT NULL THEN 'Recebida'
      WHEN se1.data_vencimento < CURRENT_DATE() THEN 'Vencida'
      ELSE 'A receber'
    END AS status_titulo,
    CASE
      WHEN se1.data_baixa IS NOT NULL THEN 'Realizado'
      WHEN se1.data_vencimento <= CURRENT_DATE() THEN 'Vencido'
      WHEN se1.data_vencimento <= DATE_ADD(CURRENT_DATE(), 30) THEN 'Proxima 30 dias'
      ELSE 'Futuro'
    END AS categoria_fluxo,
    se1.cod_parceiro,
    se1.tipo_titulo,
    se1.protheus_pk,
    se1.mdmCounterForEntity
  FROM se1_receber_base AS se1
  WHERE se1.ranking = 1
    AND (se1.mdmDeleted = FALSE OR se1.mdmDeleted IS NULL)
),

saidas_caixa AS (
  SELECT
    'SAIDA' AS tipo_fluxo,
    se2.mdmTenantId,
    se2.company_group,
    se2.filial,
    COALESCE(se2.data_baixa, se2.data_vencimento_real, se2.data_vencimento) AS data_movimento,
    se2.prefixo,
    se2.numero,
    se2.parcela,
    CONCAT(se2.prefixo, '-', se2.numero, '-', se2.parcela) AS titulo_identificacao,
    se2.valor_original AS valor_movimento,
    CASE
      WHEN se2.data_baixa IS NOT NULL THEN 'Paga'
      WHEN se2.data_vencimento < CURRENT_DATE() THEN 'Vencida'
      ELSE 'A pagar'
    END AS status_titulo,
    CASE
      WHEN se2.data_baixa IS NOT NULL THEN 'Realizado'
      WHEN se2.data_vencimento <= CURRENT_DATE() THEN 'Vencido'
      WHEN se2.data_vencimento <= DATE_ADD(CURRENT_DATE(), 30) THEN 'Proxima 30 dias'
      ELSE 'Futuro'
    END AS categoria_fluxo,
    se2.cod_parceiro,
    se2.tipo_titulo,
    se2.protheus_pk,
    se2.mdmCounterForEntity
  FROM se2_pagar_base AS se2
  WHERE se2.ranking = 1
    AND (se2.mdmDeleted = FALSE OR se2.mdmDeleted IS NULL)
),

visao_fluxo_completa AS (
  SELECT * FROM entradas_caixa
  UNION ALL
  SELECT * FROM saidas_caixa
),

fluxo_caixa_agregado AS (
  SELECT
    mdmTenantId,
    company_group,
    filial,
    data_movimento,
    tipo_fluxo,
    categoria_fluxo,
    COUNT(*) AS quantidade_titulos,
    SUM(CASE WHEN tipo_fluxo = 'ENTRADA' THEN valor_movimento ELSE 0 END) AS total_entradas,
    SUM(CASE WHEN tipo_fluxo = 'SAIDA' THEN valor_movimento ELSE 0 END) AS total_saidas,
    SUM(CASE WHEN tipo_fluxo = 'ENTRADA' THEN valor_movimento ELSE -valor_movimento END) AS saldo_liquido,
    date_format(data_movimento, 'yyyy-MM') AS competencia,
    protheus_pk,
    mdmCounterForEntity
  FROM visao_fluxo_completa
  WHERE data_movimento IS NOT NULL
  GROUP BY
    mdmTenantId,
    company_group,
    filial,
    data_movimento,
    tipo_fluxo,
    categoria_fluxo,
    competencia,
    protheus_pk,
    mdmCounterForEntity
),

fluxo_caixa_acumulado AS (
  SELECT
    *,
    SUM(saldo_liquido) OVER (
      PARTITION BY mdmTenantId, company_group, filial
      ORDER BY data_movimento
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS saldo_acumulado,
    SUM(saldo_liquido) OVER (
      PARTITION BY mdmTenantId, company_group, filial, competencia
      ORDER BY data_movimento
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS saldo_competencia
  FROM fluxo_caixa_agregado
)

SELECT
  *,
  CONCAT(CAST(protheus_pk AS STRING), '_', SUBSTR(md5(CAST(RAND() AS STRING)), 1, 8)) AS __mdmId,
  0 AS __mdmCounterForEntity
FROM fluxo_caixa_acumulado
