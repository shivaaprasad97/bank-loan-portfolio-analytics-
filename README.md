# Bank Loan Portfolio Analytics Dashboard

An end-to-end analytics project covering the full pipeline from raw data to a published, interactive dashboard: data modeling in **Snowflake**, star-schema design, SQL-based reconciliation, and visualization in **Tableau Public**.

**Live Dashboard:** [https://public.tableau.com/views/BankloanportfolioAnalyticsDashboard/BankLoanPortfolioOverview?:language=en-US&:sid=&:redirect=auth&:display_count=n&:origin=viz_share_link]

---

## Project Overview

This project analyzes a portfolio of ~10,000 consumer loans (the `loans_full_schema` dataset, similar in structure to Lending Club's public loan data) to answer core business questions a bank's risk and portfolio management teams would ask:

- What does our total loan volume and pricing (interest rate) look like?
- Which loan grades carry the highest default risk?
- How is loan origination trending over time?
- Does credit utilization correlate with default risk?

The goal was to replicate a real BI analyst workflow end to end — not just build charts, but design a proper dimensional model, validate data quality at each stage, and document findings the way a production reporting pipeline would.

---

## Tech Stack

| Layer | Tool |
|---|---|
| Data Warehouse | Snowflake |
| Data Modeling | Star schema (SQL DDL) |
| Transformation | SQL (CTEs, joins, window functions) |
| Visualization | Tableau Public |
| Source Data | Public loan-level dataset (~10,000 rows, 56 raw columns) |

---

## Data Architecture

### Raw Layer
All 56 source columns loaded as-is into `RAW.LOANS_RAW` in Snowflake via a staged `COPY INTO`, with explicit `NULL_IF` handling for text nulls (`'NA'`, `'N/A'`, blanks) that a simple UI-based load could not parse correctly.

### Star Schema (Analytics Layer)
| Table | Grain | Key Fields |
|---|---|---|
| `FACT_LOANS` | One row per loan | loan_amount, interest_rate, balance, paid_total, is_default_flag, is_paid_off_flag |
| `DIM_DATE` | One row per issue month | issue_year, issue_month_num, issue_quarter |
| `DIM_BORROWER` | One row per loan (1:1 in this dataset) | employment, income, homeownership, income_band |
| `DIM_CREDIT_PROFILE` | One row per loan | credit utilization, delinquencies, inquiries, collections |
| `DIM_LOAN_PRODUCT` | One row per distinct product combination | loan_purpose, term, grade, sub_grade |

Full DDL and transformation SQL: see `lending_club_star_schema.sql`.

---

## Data Quality & Reconciliation

Every stage of the pipeline was validated before moving to reporting:

- **Null profiling** on raw data confirmed 100% completeness on core financial fields (loan amount, interest rate, income), with expected gaps only in optional fields like employment title (~8%).
- **Duplicate check** confirmed the loan ID (`row_id`) is a clean, unique grain key.
- **Row-count and dollar-total reconciliation** between the raw layer and `FACT_LOANS` caught a **fan-out join bug**: an early version of `DIM_LOAN_PRODUCT` was built with a finer grain (6 columns) than the fact table's join key (4 columns), silently multiplying the fact table from 10,000 rows to over 1 million. This was root-caused by comparing row counts and dollar totals at each layer, then fixed by moving the two extra attributes (`initial_listing_status`, `disbursement_method`) directly onto the fact table where they belong. Post-fix, raw and fact row counts and dollar totals reconcile exactly (10,000 = 10,000; totals match to the cent).

---

## Key Findings

- **Total loan volume:** $163.6M across the portfolio
- **Average interest rate:** 12.43%
- **Default rates increase with loan grade risk** (A through D), consistent with expected credit risk behavior — though grades E–G show 0% defaults, which is a small-sample effect (very few loans in those grades) rather than an absence of risk.
- **Loan originations grew steadily** over the available data window (a short, few-month origination snapshot rather than a multi-year history).
- **Credit utilization** across the portfolio is right-skewed: most borrowers cluster in the 5–25% utilization range, with a long tail extending toward much higher utilization — informing which segment(s) merit closer risk monitoring.

---

## What This Project Demonstrates

- Dimensional modeling (star schema) from a flat source file
- SQL data quality checks: null profiling, duplicate detection, reconciliation
- Root-cause debugging of a real data pipeline defect (fan-out join)
- KPI and DAX/calculated-field development for business reporting
- Dashboard design combining KPIs, trend, and risk-segmentation visuals
- Adapting a technical plan under real constraints (pivoted from Power BI to Tableau due to platform availability) without losing the underlying data engineering work

---

## Files in This Repo

- `lending_club_star_schema.sql` — full Snowflake DDL, transformation, and reconciliation SQL
- `README.md` — this file
