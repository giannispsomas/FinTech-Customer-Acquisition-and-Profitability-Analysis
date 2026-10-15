# FinTech Customer Acquisition and Profitability Analysis

Which acquisition channels bring profitable customers, and how should a neobank reallocate next quarter's marketing budget? The project works with a synthetic dataset for a fictional bank (Meltemi Bank) and takes it through SQL Server, Excel and Power BI.

**Tools:** SQL Server, Excel (Solver), Power BI

> The data is **synthetic**. It was generated with Python (fixed seed). The credit part is shaped after LendingClub's published grade mix and APR range. Default rates and all marketing and banking behaviour are assumptions. The bank, its customers and its numbers are not real.

*Results sections are filled in as each part of the project is finished.*

## Project overview

**Business problem:** which acquisition channels bring customers who pay back their cost, and how should the budget move between channels?

**Approach:**
1. [SQL](sql/): profile and clean the raw data, then define every metric once in SQL views.
2. Excel: unit economics, response curves and a Solver budget optimizer.
3. Power BI: pages for the executive summary, funnel, attribution and campaigns, and credit risk.

The data goes through three layers: `dbo` (raw, never changed), `clean` (cleaned copy) and `rpt` (reporting views).

## Repository structure

```
.
├── README.md
├── data_profiling.md       what is wrong with the raw data
├── data_cleaning.md        what I did about it
├── data/                   the 10 synthetic CSV files
└── sql/
    ├── profiling/          93 read-only checks, one file per table
    ├── clean/              one script per table, builds the clean layer
    ├── rpt/                reporting views (to come)
    └── archive/            old scripts, not used
```

## Documentation

| Document | What it covers |
|---|---|
| [data_profiling.md](data_profiling.md) | The 93 checks, the 18 findings and the decision for each |
| [data_cleaning.md](data_cleaning.md) | The cleaning rules, the row count log and the validation |
| [sql/README.md](sql/README.md) | The run order of the SQL scripts |

## Dataset

- **Source:** synthetic, generated with Python.
- **Tables:** channels, campaigns, daily_ad_spend, customers, touchpoints, accounts, transactions, loans, repayments, assumptions.
- **Size:** 136,098 rows over 24 months (October 2024 to September 2026).
- **Messiness:** the raw tables contain planted data quality problems, such as duplicates, spelling variants and sign errors.

## Definitions

- **Acquired customer:** a customer with a first deposit (a funded customer).
- **CAC:** (ad spend + EUR 2.50 per KYC decision) divided by funded customers.
- **Seasoned loan:** issued on or before 2026-03-31. Default rates use only these loans.

The full list of definitions will be added with the metric dictionary.

## Reproducing the project

1. Load the CSV files from `data/` into a SQL Server database with the Import Flat File wizard. Put the tables in schema `dbo`.
2. Optional: run the scripts in `sql/profiling/` to see the checks.
3. Run the scripts in `sql/clean/` in number order (`01` to `10`).
4. Reporting views, the Excel model and the Power BI report will be added.

## About the author

Giannis Psomas. Data analyst portfolio project.

## License

The code is released under the MIT License. The data is synthetic.
