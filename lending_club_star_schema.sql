/* ============================================================
   LENDING CLUB BANKING ANALYTICS PROJECT
   Dataset: loans_full_schema.csv (10,000 rows, 56 columns)
   Platform: Snowflake
   Author: Shivaprasad
   ============================================================
   STEP 0: SETUP
   ============================================================ */

CREATE WAREHOUSE IF NOT EXISTS BANK_WH WITH WAREHOUSE_SIZE = 'XSMALL' AUTO_SUSPEND = 60 AUTO_RESUME = TRUE;
CREATE DATABASE IF NOT EXISTS BANK_ANALYTICS;
CREATE SCHEMA IF NOT EXISTS BANK_ANALYTICS.RAW;
CREATE SCHEMA IF NOT EXISTS BANK_ANALYTICS.ANALYTICS;

USE WAREHOUSE BANK_WH;
USE DATABASE BANK_ANALYTICS;

/* ============================================================
   STEP 1: RAW STAGING TABLE (mirrors the CSV as-is)
   Load with Snowsight's "Load Data" wizard (UI) pointing at this
   table, or use PUT + COPY INTO if using SnowSQL.
   ============================================================ */

CREATE OR REPLACE TABLE RAW.LOANS_RAW (
    row_id                              INTEGER,     -- 'Unnamed: 0' in the CSV
    emp_title                           STRING,
    emp_length                          FLOAT,
    state                               STRING,
    homeownership                       STRING,
    annual_income                       FLOAT,
    verified_income                     STRING,
    debt_to_income                      FLOAT,
    annual_income_joint                 FLOAT,
    verification_income_joint           STRING,
    debt_to_income_joint                FLOAT,
    delinq_2y                           INTEGER,
    months_since_last_delinq            FLOAT,
    earliest_credit_line                INTEGER,      -- year, e.g. 2001
    inquiries_last_12m                  INTEGER,
    total_credit_lines                  INTEGER,
    open_credit_lines                   INTEGER,
    total_credit_limit                  FLOAT,
    total_credit_utilized               FLOAT,
    num_collections_last_12m            INTEGER,
    num_historical_failed_to_pay        INTEGER,
    months_since_90d_late               FLOAT,
    current_accounts_delinq             INTEGER,
    total_collection_amount_ever        FLOAT,
    current_installment_accounts        INTEGER,
    accounts_opened_24m                 INTEGER,
    months_since_last_credit_inquiry    FLOAT,
    num_satisfactory_accounts           INTEGER,
    num_accounts_120d_past_due          FLOAT,
    num_accounts_30d_past_due           INTEGER,
    num_active_debit_accounts           INTEGER,
    total_debit_limit                   FLOAT,
    num_total_cc_accounts               INTEGER,
    num_open_cc_accounts                INTEGER,
    num_cc_carrying_balance             INTEGER,
    num_mort_accounts                   INTEGER,
    account_never_delinq_percent        FLOAT,
    tax_liens                           INTEGER,
    public_record_bankrupt              INTEGER,
    loan_purpose                        STRING,
    application_type                    STRING,
    loan_amount                         FLOAT,
    term                                INTEGER,      -- months, 36 or 60
    interest_rate                       FLOAT,
    installment                         FLOAT,
    grade                               STRING,
    sub_grade                           STRING,
    issue_month                         STRING,       -- e.g. 'Jan-2018'
    loan_status                         STRING,
    initial_listing_status              STRING,
    disbursement_method                 STRING,
    balance                             FLOAT,
    paid_total                          FLOAT,
    paid_principal                      FLOAT,
    paid_interest                       FLOAT,
    paid_late_fees                      FLOAT
);

-- Example load (run via Snowsight UI wizard, or SnowSQL):
-- PUT file:///local/path/loans_full_schema.csv @%LOANS_RAW;
-- COPY INTO RAW.LOANS_RAW
--   FROM @%LOANS_RAW
--   FILE_FORMAT = (TYPE = CSV SKIP_HEADER = 1 FIELD_OPTIONALLY_ENCLOSED_BY='"' NULL_IF = ('', 'NA', 'N/A'))
--   ON_ERROR = 'CONTINUE';

/* ============================================================
   STEP 2: DATA QUALITY CHECK ON RAW LAYER
   (documents your "data quality / validation" resume bullet)
   ============================================================ */

-- Row count check
SELECT COUNT(*) AS raw_row_count FROM RAW.LOANS_RAW;

-- Null profiling on key fields
SELECT
    COUNT(*)                                              AS total_rows,
    COUNT(*) - COUNT(loan_amount)                         AS missing_loan_amount,
    COUNT(*) - COUNT(interest_rate)                       AS missing_interest_rate,
    COUNT(*) - COUNT(annual_income)                       AS missing_annual_income,
    COUNT(*) - COUNT(emp_title)                            AS missing_emp_title,
    COUNT(*) - COUNT(debt_to_income)                       AS missing_dti
FROM RAW.LOANS_RAW;

-- Duplicate check on grain (row_id should be unique)
SELECT row_id, COUNT(*) AS cnt
FROM RAW.LOANS_RAW
GROUP BY row_id
HAVING COUNT(*) > 1;

/* ============================================================
   STEP 3: DIMENSION TABLES
   ============================================================ */

-- DIM_DATE ---------------------------------------------------
CREATE OR REPLACE TABLE ANALYTICS.DIM_DATE AS
SELECT
    ROW_NUMBER() OVER (ORDER BY issue_month) AS date_key,
    issue_month                                AS issue_month_raw,
    TO_DATE('01-' || issue_month, 'DD-MON-YYYY') AS issue_date,
    YEAR(TO_DATE('01-' || issue_month, 'DD-MON-YYYY'))  AS issue_year,
    MONTH(TO_DATE('01-' || issue_month, 'DD-MON-YYYY')) AS issue_month_num,
    MONTHNAME(TO_DATE('01-' || issue_month, 'DD-MON-YYYY')) AS issue_month_name,
    CEIL(MONTH(TO_DATE('01-' || issue_month, 'DD-MON-YYYY')) / 3.0) AS issue_quarter
FROM (SELECT DISTINCT issue_month FROM RAW.LOANS_RAW WHERE issue_month IS NOT NULL);

-- DIM_BORROWER -------------------------------------------------
CREATE OR REPLACE TABLE ANALYTICS.DIM_BORROWER AS
SELECT
    row_id                          AS borrower_key,   -- 1:1 with loan in this dataset (no repeat customers)
    emp_title,
    emp_length,
    state,
    homeownership,
    annual_income,
    verified_income,
    debt_to_income,
    annual_income_joint,
    verification_income_joint,
    debt_to_income_joint,
    application_type,
    CASE
        WHEN annual_income < 40000 THEN 'Under 40K'
        WHEN annual_income < 80000 THEN '40K-80K'
        WHEN annual_income < 120000 THEN '80K-120K'
        ELSE '120K+'
    END AS income_band
FROM RAW.LOANS_RAW;

-- DIM_CREDIT_PROFILE --------------------------------------------
CREATE OR REPLACE TABLE ANALYTICS.DIM_CREDIT_PROFILE AS
SELECT
    row_id                              AS credit_profile_key,
    delinq_2y,
    months_since_last_delinq,
    earliest_credit_line,
    inquiries_last_12m,
    total_credit_lines,
    open_credit_lines,
    total_credit_limit,
    total_credit_utilized,
    ROUND(total_credit_utilized / NULLIF(total_credit_limit, 0) * 100, 1) AS credit_utilization_pct,
    num_collections_last_12m,
    num_historical_failed_to_pay,
    months_since_90d_late,
    current_accounts_delinq,
    total_collection_amount_ever,
    current_installment_accounts,
    accounts_opened_24m,
    months_since_last_credit_inquiry,
    num_satisfactory_accounts,
    num_accounts_120d_past_due,
    num_accounts_30d_past_due,
    num_active_debit_accounts,
    total_debit_limit,
    num_total_cc_accounts,
    num_open_cc_accounts,
    num_cc_carrying_balance,
    num_mort_accounts,
    account_never_delinq_percent,
    tax_liens,
    public_record_bankrupt
FROM RAW.LOANS_RAW;

-- DIM_LOAN_PRODUCT ------------------------------------------------
CREATE OR REPLACE TABLE ANALYTICS.DIM_LOAN_PRODUCT AS
SELECT DISTINCT
    ROW_NUMBER() OVER (ORDER BY loan_purpose, term, grade, sub_grade) AS loan_product_key,
    loan_purpose,
    term,
    grade,
    sub_grade,
    initial_listing_status,
    disbursement_method
FROM RAW.LOANS_RAW;

/* ============================================================
   STEP 4: FACT TABLE
   Grain: one row per loan
   ============================================================ */

CREATE OR REPLACE TABLE ANALYTICS.FACT_LOANS AS
SELECT
    r.row_id                                            AS loan_key,
    d.date_key,
    r.row_id                                            AS borrower_key,        -- matches DIM_BORROWER
    r.row_id                                            AS credit_profile_key,  -- matches DIM_CREDIT_PROFILE
    p.loan_product_key,
    r.loan_amount,
    r.interest_rate,
    r.installment,
    r.balance,
    r.paid_total,
    r.paid_principal,
    r.paid_interest,
    r.paid_late_fees,
    r.loan_status,
    CASE
        WHEN r.loan_status IN ('Charged Off', 'Default') THEN 1
        ELSE 0
    END AS is_default_flag,
    CASE
        WHEN r.loan_status = 'Fully Paid' THEN 1
        ELSE 0
    END AS is_paid_off_flag,
    ROUND(r.paid_total - r.loan_amount, 2)              AS net_gain_loss
FROM RAW.LOANS_RAW r
LEFT JOIN ANALYTICS.DIM_DATE d
    ON r.issue_month = d.issue_month_raw
LEFT JOIN ANALYTICS.DIM_LOAN_PRODUCT p
    ON  r.loan_purpose = p.loan_purpose
    AND r.term = p.term
    AND r.grade = p.grade
    AND r.sub_grade = p.sub_grade;

/* ============================================================
   STEP 5: RECONCILIATION CHECK
   (mirrors your "source-to-report reconciliation" resume bullet)
   ============================================================ */

SELECT
    (SELECT COUNT(*) FROM RAW.LOANS_RAW)        AS raw_count,
    (SELECT COUNT(*) FROM ANALYTICS.FACT_LOANS) AS fact_count,
    (SELECT COUNT(*) FROM RAW.LOANS_RAW) - (SELECT COUNT(*) FROM ANALYTICS.FACT_LOANS) AS row_count_diff,
    (SELECT ROUND(SUM(loan_amount),2) FROM RAW.LOANS_RAW)        AS raw_total_loan_amt,
    (SELECT ROUND(SUM(loan_amount),2) FROM ANALYTICS.FACT_LOANS) AS fact_total_loan_amt;

-- Loans that failed to match a loan_product_key (data quality flag)
SELECT loan_key, loan_amount, loan_status
FROM ANALYTICS.FACT_LOANS
WHERE loan_product_key IS NULL;

/* ============================================================
   STEP 6: SAMPLE ANALYTICAL QUERIES (SQL depth for resume/interview talking points)
   ============================================================ */

-- Default rate by grade
SELECT
    p.grade,
    COUNT(*)                                   AS total_loans,
    SUM(f.is_default_flag)                     AS defaults,
    ROUND(SUM(f.is_default_flag) * 100.0 / COUNT(*), 2) AS default_rate_pct
FROM ANALYTICS.FACT_LOANS f
JOIN ANALYTICS.DIM_LOAN_PRODUCT p ON f.loan_product_key = p.loan_product_key
GROUP BY p.grade
ORDER BY p.grade;

-- Portfolio trend by issue month (window function example)
SELECT
    d.issue_year,
    d.issue_month_num,
    SUM(f.loan_amount) AS monthly_originations,
    SUM(SUM(f.loan_amount)) OVER (ORDER BY d.issue_year, d.issue_month_num) AS running_total_originations
FROM ANALYTICS.FACT_LOANS f
JOIN ANALYTICS.DIM_DATE d ON f.date_key = d.date_key
GROUP BY d.issue_year, d.issue_month_num
ORDER BY d.issue_year, d.issue_month_num;

-- Credit utilization vs default rate (risk analysis)
SELECT
    CASE
        WHEN c.credit_utilization_pct < 30 THEN 'Low (<30%)'
        WHEN c.credit_utilization_pct < 60 THEN 'Medium (30-60%)'
        ELSE 'High (60%+)'
    END AS utilization_band,
    COUNT(*) AS loan_count,
    ROUND(AVG(f.is_default_flag) * 100, 2) AS default_rate_pct
FROM ANALYTICS.FACT_LOANS f
JOIN ANALYTICS.DIM_CREDIT_PROFILE c ON f.credit_profile_key = c.credit_profile_key
GROUP BY 1
ORDER BY 1;
