# FinTech Customer Acquisition and Profitability Analysis

An analysis of customer acquisition for a fictional neobank (Meltemi Bank): 10,000 customers, 24 months and about 136,000 rows across 10 tables. The project takes raw data through SQL Server and Excel to answer one question: **which acquisition channels bring profitable customers, and how should next quarter's marketing budget be reallocated?**

**Tools:** SQL Server (T-SQL) · Excel (Solver) · Power BI

**Start here:** [Case study](Case_Study.md) · [Dashboard report (PDF)](power_bi/Customer_Acquisition_Analysis.pdf) · [One-page summary (PDF)](Executive_Summary.pdf)

> The data is **synthetic**. It was generated with Python (fixed seed). The credit part is shaped after LendingClub's published grade mix and APR range. Default rates and all marketing and banking behaviour are assumptions. The bank, its customers and its numbers are not real.

### At a glance

- **Before credit loss, every paid channel pays back its acquisition cost within 12 months** (referral in month 2, paid social in month 6). **After credit loss, only referral earns money per customer** (+54 EUR, against -28 to -491 EUR for the other channels).
- **Affiliate has the best 12-month value (252 EUR per customer) but the worst credit risk:** 24% of its seasoned loans default, against 6.5% to 12.5% elsewhere, concentrated in students.
- **Paid social is the most expensive channel** (CAC 65.59 EUR) and **one campaign wastes money:** SO_Summer_Reach_2026 costs 365 EUR per customer against a channel median of 62.
- **The model's best allocation** puts affiliate, paid search and paid social at half of their baseline spend and referral 20% above it. It improves the quarter by about 40,700 EUR, but the net result stays negative because loan losses dominate. The biggest lever is credit policy, not channel mix.

**Skills shown:** data profiling and cleaning in T-SQL · reporting views with window functions and CTEs · attribution (first touch, last touch, position-based) · payback and LTV by cohort of months · response curves, Solver optimization and scenarios in Excel · a five-page Power BI report with DAX measures · documenting assumptions and limits honestly.

## Key Findings and Recommendations

The story from question to recommendation is in the **[Case Study](Case_Study.md)**. The findings for each of the five supporting questions and the headline question are in **[Business_Questions.md](docs/Business_Questions.md)**. The recommendation is a hypothesis drawn from simulated data and has not been tested. See [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md).

## Project Overview

**Business problem:** which acquisition channels bring customers who pay back their cost, and how should the budget move between channels?

**Approach**

1. **SQL Server:** profile and clean the raw data, then define every metric once in reporting views ([sql/](sql/)).
2. **Excel:** unit economics, response curves per channel and a Solver budget optimizer with scenarios ([excel/](excel/)).

3. **Power BI:** a five-page report on the reporting views and the Excel results, with 41 DAX measures ([power_bi/](power_bi/)).

The data goes through three layers: `dbo` (raw, never changed), `clean` (cleaned copy) and `rpt` (reporting views).

## Dashboard

The report has five pages: Executive, Funnel, Attribution and campaigns, Credit risk, and Budget scenarios. The full PDF is [power_bi/Customer_Acquisition_Analysis.pdf](power_bi/Customer_Acquisition_Analysis.pdf), and every page is explained in [Report_Guide.md](docs/Report_Guide.md).

![Executive page](power_bi/images/1_Executive.png)

![Credit risk page](power_bi/images/4_Credit_Risk.png)

## Repository Structure

```
FinTech-Customer-Acquisition-and-Profitability-Analysis/
├── README.md                        Project overview (this file)
├── Case_Study.md                    The question, method, findings and recommendations
├── Case_Study.pdf                   The same case study as a PDF
├── Executive_Summary.pdf            One-page summary for business readers
├── LICENSE                          MIT license
├── data/                            The 10 synthetic CSV files
├── docs/                            Supporting documentation
│   ├── data_profiling.md            Profiling of the raw data
│   ├── data_cleaning.md             Cleaning steps and row counts
│   ├── reporting_views.md           The reporting layer: grain, rules and checks of each view
│   ├── Business_Questions.md        Business questions, methods and findings
│   ├── Assumptions_and_Limitations.md   Definitions, assumptions and limits
│   ├── DAX_Measures.md              The 41 DAX measures of the report
│   └── Report_Guide.md              Page-by-page guide to the Power BI report
├── sql/                             T-SQL scripts (profiling, cleaning, reporting views, business questions)
│   ├── 01_data_profiling.sql
│   ├── 02_data_cleaning.sql
│   ├── 03_reporting_views.sql
│   └── 04_business_questions.sql
├── excel/                           Excel model
│   ├── budget_model.xlsx            Unit economics, response curves, Solver optimizer, scenarios
│   └── Excel_Model_Walkthrough.pdf  Sheet-by-sheet walkthrough of the model, as a worked example
└── power_bi/                        Power BI report
    ├── Customer_Acquisition_Analysis.pbix   The report (5 pages)
    ├── Customer_Acquisition_Analysis.pdf    PDF export of the report
    ├── Customer_Acquisition_Theme.json      Colour theme
    └── images/                      One screenshot per page
```

## Documentation

| Document | What it covers |
|---|---|
| [data_profiling.md](docs/data_profiling.md) | The 93 checks, the 18 findings and the decision for each |
| [data_cleaning.md](docs/data_cleaning.md) | The cleaning rules, the row count log and the validation |
| [reporting_views.md](docs/reporting_views.md) | The ten reporting views, their design decisions and checks |
| [Business_Questions.md](docs/Business_Questions.md) | Each business question, its method and its finding |
| [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md) | Definitions, assumptions, and what the analysis cannot conclude |
| [DAX_Measures.md](docs/DAX_Measures.md) | Every DAX measure of the report, its formula and the number to check it against |
| [Report_Guide.md](docs/Report_Guide.md) | The data model and a page-by-page guide to the Power BI report |

## Dataset

- **Source:** synthetic, generated with Python.
- **Tables:** channels, campaigns, daily_ad_spend, customers, touchpoints, accounts, transactions, loans, repayments, assumptions.
- **Size:** 136,098 rows over 24 months (October 2024 to September 2026). The extract date is 2026-09-30.
- **Messiness:** the raw tables contain data quality problems, such as duplicates, spelling variants and sign errors. 100 duplicate customer records are removed in the cleaning step, which leaves 10,000 customers.

> The CSV files are included in `data/` because the data is synthetic and small enough to share.

## Definitions and Assumptions

The full list is in [Assumptions_and_Limitations.md](docs/Assumptions_and_Limitations.md). The key ones:

- **Funded customer:** a customer with a first deposit. This is the acquired customer.
- **CAC:** (ad spend + 2.50 EUR per KYC decision) divided by funded customers. Organic has no ad spend, so it has no CAC.
- **LTV:** the observed margin per customer over the first 12 months. **Risk-adjusted LTV** subtracts the credit loss on that customer's loans.
- **Seasoned loan:** issued on or before 2026-03-31. Default rates use only seasoned loans.
- **Attribution:** position-based credit (40% first click, 40% last click, 20% shared by the middle clicks), compared with first touch, last touch and the recorded channel.

## Reproducing the Project

### Environment
- SQL Server (developed on SQL Server Express) and SQL Server Management Studio
- Excel with the Solver add-in enabled
- Power BI Desktop (to open the report)

### Steps

1. **Create the database.** Create a database named `NeobankGrowth`.
2. **Load the data into SQL Server.** Load the CSV files from `data/` into schema `dbo` with the **Import Flat File** wizard in SQL Server Management Studio; there is no import script. Use the table names `channels`, `campaigns`, `daily_ad_spend`, `customers`, `touchpoints`, `accounts`, `transactions`, `loans`, `repayments` and `assumptions`.
3. **Run the SQL scripts** in [sql/](sql/) in numbered order, from `01_data_profiling.sql` through `04_business_questions.sql`. `01` only reads. `02` builds the clean tables, `03` builds the reporting views, and `04` holds the analysis queries.
4. **Open the Excel model** in [excel/](excel/). The data sheets hold the results of the SQL views. To refresh them, run the views again and paste the results. Press Solve in the `Optimizer` sheet to rerun the optimization.
5. **Open the Power BI report** [power_bi/Customer_Acquisition_Analysis.pbix](power_bi/Customer_Acquisition_Analysis.pbix). It reads the `rpt` views from the `NeobankGrowth` database on `.\SQLEXPRESS` with Windows authentication, and the two result tables from `excel/budget_model.xlsx`. If your server or file path differs, change the data source in Transform data, then Data source settings.

## About the author

Giannis Psomas. Data analyst portfolio project.

- LinkedIn: [giannispsomas](https://www.linkedin.com/in/giannispsomas)
- GitHub: [giannispsomas](https://github.com/giannispsomas)

## License

The code in this repository is released under the [MIT License](LICENSE). The data is synthetic.
