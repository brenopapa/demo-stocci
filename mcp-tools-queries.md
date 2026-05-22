# MCP Tools - PostgreSQL Queries

## Clientes

### 1. find_customers_semantic
**Type:** Embedding-based search  
**Purpose:** User describes customer → find matching customers by name/location/type

```sql
WITH candidates AS (
  SELECT
    cod_cliente,
    loja,
    A1_NOME,
    cnpj_cpf,
    municipio,
    estado,
    tipo_cliente,
    email,
    risco_credito,
    1 - (embedded_content_128 <=> ${embedding}::vector) AS score
  FROM sa1_clientes
  WHERE embedded_content_128 IS NOT NULL
  ORDER BY embedded_content_128 <=> ${embedding}::vector
  LIMIT 30
)
SELECT
  cod_cliente,
  loja,
  A1_NOME,
  cnpj_cpf,
  municipio,
  estado,
  tipo_cliente,
  email,
  risco_credito,
  score
FROM candidates
WHERE score >= 0.55
ORDER BY score DESC
LIMIT 5;
```

**Parameters:** `embedding` (vector[128])  
**Returns:** customer_id, name, cnpj, location, type, email, credit_risk, similarity_score

---

### 2. get_customer_risk
**Type:** Direct SQL  
**Purpose:** Check credit risk for customer ID

```sql
SELECT
  cod_cliente,
  loja,
  A1_NOME,
  cnpj_cpf,
  tipo_cliente,
  limite_credito,
  saldo_duplicatas,
  risco_credito,
  status_bloqueio,
  email
FROM sa1_clientes
WHERE cod_cliente = ${customer_id}
LIMIT 1;
```

**Parameters:** `customer_id` (string)  
**Returns:** customer info, credit_limit, outstanding_balance, risk_classification, blocking_status

---

### 3. list_customers_overdue
**Type:** Direct SQL (aggregated)  
**Purpose:** Get customers with overdue invoices + aging breakdown

```sql
SELECT
  c.cod_cliente,
  c.loja,
  c.A1_NOME,
  c.cnpj_cpf,
  c.email,
  c.municipio,
  SUM(f.saldo_aberto) AS total_em_aberto,
  COUNT(*) AS qtd_titulos_vencidos,
  COUNT(DISTINCT f.faixa_aging) AS qtd_faixas_vencimento,
  MAX(f.data_vencimento) AS vencimento_mais_antigo,
  MAX(CASE WHEN f.faixa_aging LIKE 'Vencido%' THEN f.dias_vencimento ELSE NULL END) AS dias_atraso_maximo
FROM sa1_clientes c
INNER JOIN financeiro_ai f ON c.cod_cliente = f.cod_parceiro AND f.carteira = 'RECEBER'
WHERE f.faixa_aging LIKE 'Vencido%'
  AND f.saldo_aberto > 0
GROUP BY c.cod_cliente, c.loja, c.A1_NOME, c.cnpj_cpf, c.email, c.municipio
ORDER BY total_em_aberto DESC
LIMIT 20;
```

**Parameters:** none  
**Returns:** customer info, total_outstanding, invoice_count, aging_breakdown, oldest_due_date

---

## Fornecedores

### 4. find_suppliers_semantic
**Type:** Embedding-based search  
**Purpose:** User types criteria → find suppliers

```sql
WITH candidates AS (
  SELECT
    cod_fornecedor,
    loja,
    A2_NOME,
    cnpj_cpf,
    municipio,
    estado,
    tipo_fornecedor,
    email,
    status_operacional,
    1 - (embedded_content_128 <=> ${embedding}::vector) AS score
  FROM sa2_fornecedores
  WHERE embedded_content_128 IS NOT NULL
  ORDER BY embedded_content_128 <=> ${embedding}::vector
  LIMIT 30
)
SELECT
  cod_fornecedor,
  loja,
  A2_NOME,
  cnpj_cpf,
  municipio,
  estado,
  tipo_fornecedor,
  email,
  status_operacional,
  score
FROM candidates
WHERE score >= 0.55
ORDER BY score DESC
LIMIT 5;
```

**Parameters:** `embedding` (vector[128])  
**Returns:** supplier_id, name, cnpj, location, type, email, operational_status, similarity_score

---

### 5. get_supplier_status
**Type:** Direct SQL  
**Purpose:** Get supplier payment terms, blocking status, balance

```sql
SELECT
  cod_fornecedor,
  loja,
  A2_NOME,
  cnpj_cpf,
  tipo_fornecedor,
  cond_pagamento,
  banco_preferencial,
  agencia_preferencial,
  conta_preferencial,
  status_bloqueio,
  status_operacional,
  saldo_duplicatas,
  email,
  telefone
FROM sa2_fornecedores
WHERE cod_fornecedor = ${supplier_id}
LIMIT 1;
```

**Parameters:** `supplier_id` (string)  
**Returns:** supplier info, payment_terms, preferred_bank, blocking_status, operational_status, balance

---

## Financeiro

### 6. get_cash_position
**Type:** Direct SQL (aggregated)  
**Purpose:** Current cash position + next 30/60/90 days forecast

```sql
SELECT
  carteira,
  SUM(CASE WHEN dias_vencimento <= 0 AND saldo_aberto > 0 THEN saldo_aberto ELSE 0 END) AS vencido,
  SUM(CASE WHEN dias_vencimento BETWEEN 1 AND 30 AND saldo_aberto > 0 THEN saldo_aberto ELSE 0 END) AS ate_30_dias,
  SUM(CASE WHEN dias_vencimento BETWEEN 31 AND 60 AND saldo_aberto > 0 THEN saldo_aberto ELSE 0 END) AS ate_60_dias,
  SUM(CASE WHEN dias_vencimento BETWEEN 61 AND 90 AND saldo_aberto > 0 THEN saldo_aberto ELSE 0 END) AS ate_90_dias,
  SUM(CASE WHEN dias_vencimento > 90 AND saldo_aberto > 0 THEN saldo_aberto ELSE 0 END) AS apos_90_dias,
  SUM(CASE WHEN data_baixa IS NOT NULL THEN 0 ELSE saldo_aberto END) AS total_aberto
FROM financeiro_ai
WHERE saldo_aberto > 0
GROUP BY carteira;
```

**Parameters:** none  
**Returns:** portfolio (RECEBER/PAGAR), overdue, 30d_forecast, 60d_forecast, 90d_forecast, future, total_open

---

### 7. search_transactions_semantic
**Type:** Embedding-based search  
**Purpose:** User describes transaction → find similar invoices

```sql
WITH candidates AS (
  SELECT
    carteira,
    prefixo,
    numero,
    parcela,
    nome_parceiro,
    cod_parceiro,
    valor_original,
    saldo_aberto,
    data_vencimento,
    faixa_aging,
    dias_vencimento,
    desc_natureza_financeira,
    email_parceiro,
    1 - (embedded_content_128 <=> ${embedding}::vector) AS score
  FROM financeiro_ai
  WHERE embedded_content_128 IS NOT NULL
  ORDER BY embedded_content_128 <=> ${embedding}::vector
  LIMIT 30
)
SELECT
  carteira,
  prefixo,
  numero,
  parcela,
  nome_parceiro,
  cod_parceiro,
  valor_original,
  saldo_aberto,
  data_vencimento,
  faixa_aging,
  dias_vencimento,
  desc_natureza_financeira,
  email_parceiro,
  score
FROM candidates
WHERE score >= 0.55
ORDER BY score DESC
LIMIT 5;
```

**Parameters:** `embedding` (vector[128])  
**Returns:** invoice_id, portfolio, counterparty, amounts, due_date, aging, financial_nature, email, similarity_score

---

### 8. get_invoice_aging
**Type:** Direct SQL (aggregated)  
**Purpose:** Breakdown of overdue/due soon/future invoices by aging bucket

```sql
SELECT
  faixa_aging,
  COUNT(*) AS qtd_titulos,
  SUM(saldo_aberto) AS total_saldo,
  AVG(saldo_aberto) AS media_valor,
  MIN(saldo_aberto) AS min_valor,
  MAX(saldo_aberto) AS max_valor,
  COUNT(DISTINCT nome_parceiro) AS qtd_parceiros,
  COUNT(DISTINCT carteira) AS carteiras
FROM financeiro_ai
WHERE saldo_aberto > 0
  AND faixa_aging != 'Liquidado'
GROUP BY faixa_aging
ORDER BY 
  CASE faixa_aging
    WHEN 'Vencido > 360 dias' THEN 1
    WHEN 'Vencido 181-360 dias' THEN 2
    WHEN 'Vencido 91-180 dias' THEN 3
    WHEN 'Vencido 31-90 dias' THEN 4
    WHEN 'Vencido 1-30 dias' THEN 5
    WHEN 'Vence em ate 7 dias' THEN 6
    WHEN 'Vence em ate 30 dias' THEN 7
    ELSE 8
  END;
```

**Parameters:** none  
**Returns:** aging_bucket, invoice_count, total_amount, avg_amount, min_amount, max_amount, counterparty_count, portfolio_distribution

---

## Implementation Notes

- **Embedding parameters:** All `${embedding}` placeholders expect a 128-dimensional vector generated from user input
- **Similarity threshold:** 0.55 applied consistently across all embedding queries
- **Result limits:** Semantic searches limited to 5 results; aggregated queries limited to 20 rows
- **Filtering:** Queries filter on `saldo_aberto > 0` (active items only) and exclude liquidated invoices where applicable
- **Dates:** All date calculations use current date as reference point (`dias_vencimento` computed in pipeline)



---- DEMO

-- CADASTRO CLIENTE

SELECT
    tipo_alerta,
    codigo,
    loja,
    nome,
    campo,
    valor_atual
FROM (
    SELECT
        'CLIENTE_SEM_SOBRENOME' AS tipo_alerta,
        a1.a1_cod               AS codigo,
        a1.a1_loja              AS loja,
        a1.a1_nome              AS nome,
        'A1_NOME'               AS campo,
        a1.a1_nome              AS valor_atual
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND a1.a1_nome IS NOT NULL
      AND trim(a1.a1_nome) <> ''
      AND trim(a1.a1_nome) NOT LIKE '% %'
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_SEM_ENDERECO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_END',
        a1.a1_end
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND (a1.a1_end IS NULL OR trim(a1.a1_end) = '')
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_ENDERECO_CURTO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_END',
        a1.a1_end
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND a1.a1_end IS NOT NULL
      AND trim(a1.a1_end) <> ''
      AND length(trim(a1.a1_end)) < 8
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_SEM_BAIRRO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_BAIRRO',
        a1.a1_bairro
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND (a1.a1_bairro IS NULL OR trim(a1.a1_bairro) = '')
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_BAIRRO_CURTO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_BAIRRO',
        a1.a1_bairro
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND a1.a1_bairro IS NOT NULL
      AND trim(a1.a1_bairro) <> ''
      AND length(trim(a1.a1_bairro)) < 3
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_SEM_MUNICIPIO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_MUN',
        a1.a1_mun
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND (a1.a1_mun IS NULL OR trim(a1.a1_mun) = '')
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_SEM_ESTADO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_EST',
        a1.a1_est
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND (a1.a1_est IS NULL OR trim(a1.a1_est) = '')
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_ESTADO_INVALIDO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_EST',
        a1.a1_est
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND a1.a1_est IS NOT NULL
      AND trim(a1.a1_est) <> ''
      AND length(trim(a1.a1_est)) <> 2
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_SEM_CEP',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_CEP',
        a1.a1_cep
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND (a1.a1_cep IS NULL OR trim(a1.a1_cep) = '')
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'CLIENTE_CEP_INVALIDO',
        a1.a1_cod,
        a1.a1_loja,
        a1.a1_nome,
        'A1_CEP',
        a1.a1_cep
    FROM READ_1 a1
    WHERE a1.d_e_l_e_t_ = ''
      AND a1.a1_cep IS NOT NULL
      AND trim(a1.a1_cep) <> ''
      AND regexp_replace(a1.a1_cep, '[^0-9]', '', 'g') !~ '^[0-9]{8}$'
      AND a1.mdmCreated >= CURRENT_DATE - INTERVAL '1 day'
) inconsistencias
ORDER BY codigo, loja, tipo_alerta

-- CADASTRO NFS

SELECT
    tipo_alerta,
    filial,
    documento,
    serie,
    cliente,
    loja,
    emissao,
    campo,
    valor_atual
FROM (

    SELECT
        'NF_VALOR_MAIOR_1_BILHAO' AS tipo_alerta,
        trim(f2_filial)           AS filial,
        trim(f2_doc)              AS documento,
        trim(f2_serie)            AS serie,
        trim(f2_cliente)          AS cliente,
        trim(f2_loja)             AS loja,

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END                       AS emissao,

        'F2_VALBRUT'              AS campo,
        trim(f2_valbrut)          AS valor_atual

    FROM READ_NF
    WHERE NULLIF(trim(f2_valbrut), '')::numeric > 1000000000
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_VALOR_ZERO_OU_NEGATIVO',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_VALBRUT',
        trim(f2_valbrut)

    FROM READ_NF
    WHERE COALESCE(NULLIF(trim(f2_valbrut), '')::numeric, 0) <= 0
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_SEM_NUMERO',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_DOC',
        trim(f2_doc)

    FROM READ_NF
    WHERE NULLIF(trim(f2_doc), '') IS NULL
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_SEM_SERIE',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_SERIE',
        trim(f2_serie)

    FROM READ_NF
    WHERE NULLIF(trim(f2_serie), '') IS NULL
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_SEM_CLIENTE',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_CLIENTE',
        trim(f2_cliente)

    FROM READ_NF
    WHERE NULLIF(trim(f2_cliente), '') IS NULL
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_SEM_CHAVE_NFE',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_CHVNFE',
        trim(f2_chvnfe)

    FROM READ_NF
    WHERE NULLIF(trim(f2_chvnfe), '') IS NULL
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_CHAVE_NFE_INVALIDA',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_CHVNFE',
        trim(f2_chvnfe)

    FROM READ_NF
    WHERE NULLIF(trim(f2_chvnfe), '') IS NOT NULL
      AND regexp_replace(trim(f2_chvnfe), '[^0-9]', '', 'g') !~ '^[0-9]{44}$'
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_BASE_ICMS_MAIOR_QUE_TOTAL',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_BASEICM',
        trim(f2_baseicm)

    FROM READ_NF
    WHERE NULLIF(trim(f2_baseicm), '')::numeric >
          NULLIF(trim(f2_valbrut), '')::numeric
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

    UNION ALL

    SELECT
        'NF_ICMS_MAIOR_QUE_TOTAL',
        trim(f2_filial),
        trim(f2_doc),
        trim(f2_serie),
        trim(f2_cliente),
        trim(f2_loja),

        CASE
            WHEN trim(f2_emissao) ~ '^[0-9]{8}$'
                THEN to_date(trim(f2_emissao), 'YYYYMMDD')
            WHEN trim(f2_emissao) ~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
                THEN trim(f2_emissao)::date
            ELSE NULL
        END,

        'F2_VALICM',
        trim(f2_valicm)

    FROM READ_NF
    WHERE NULLIF(trim(f2_valicm), '')::numeric >
          NULLIF(trim(f2_valbrut), '')::numeric
      AND mdmCreated >= CURRENT_DATE - INTERVAL '1 day'

) inconsistencias

ORDER BY documento, serie, cliente, loja, tipo_alerta