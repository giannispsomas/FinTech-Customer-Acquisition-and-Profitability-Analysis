# Assumptions and Limitations

This document lists the definitions the analysis relies on and what it cannot conclude. Read it alongside the findings in [`Business_Questions.md`](Business_Questions.md) and the Excel model in [`excel/budget_model.xlsx`](../excel/budget_model.xlsx).

## Contents

1. [Data and scope](#1-data-and-scope)
2. [Definitions used](#2-definitions-used)
3. [Modeling assumptions](#3-modeling-assumptions)
4. [Limitations](#4-limitations)
5. [What the analysis does not claim](#5-what-the-analysis-does-not-claim)

---

## 1. Data and scope

- **Source:** a synthetic dataset for a fictional bank (Meltemi Bank), generated with Python using a fixed seed. The credit part is shaped after LendingClub's published grade mix and APR range. Default rates and all marketing and banking behaviour are assumptions. The bank, its customers and its numbers are not real.
- **Currency:** all amounts are in EUR.
- **Period:** October 2024 to September 2026. The extract date is 2026-09-30.
- **Size:** 10 tables and 136,098 rows. After the duplicate records are removed there are 10,000 customers, of whom 5,928 funded.
- **Revenue basis:** card interchange, loan interest and the loan origination fee. Deposit margin is left out because the data has no balances.
- **Organic:** it has no ad spend, so it is left out of CAC, ROAS and payback. It stays in the funnel, LTV and credit-risk comparisons as the unpaid baseline.
- **Cleaning:** the steps and row counts are in [`data_cleaning.md`](data_cleaning.md) and [`data_profiling.md`](data_profiling.md).

## 2. Definitions used

| Term | Definition |
|---|---|
| Funded customer | A customer with at least one deposit. The date of the first deposit is the acquisition date. Customers with an account but no deposit (2,353) are not funded. |
| Month | A 30-day block counted from the first deposit. Month 1 is days 0 to 29. Only the first 12 months are used. |
| Complete month | A month whose 30 days are all inside the data. Averages by month use complete months only. |
| Margin | Interchange + origination fee + loan interest - cost of funds - servicing. |
| CAC | (Ad spend + 2.50 EUR per KYC decision) divided by funded customers. A KYC decision is a verified or rejected status. |
| Ad-only CAC | Ad spend divided by funded customers. |
| ROAS | 12-month revenue per customer divided by ad-only CAC. Gross revenue, so it can look healthy when LTV/CAC is low. |
| LTV | The observed 12-month margin per customer, averaged over the customers with a complete month 12 (funded on or before 2025-10-05). Before credit loss. |
| Payback month | The first month where the average cumulative margin per customer reaches CAC. |
| Seasoned loan | A loan issued on or before 2026-03-31. Default rates use seasoned loans only, because younger loans have not had time to go 90 days late. |
| DPD | Days past due: the days between the due date and the day the installment was cleared, or the extract date if it is not cleared. Never below 0. A partial payment does not clear an installment. |
| Delinquent | Worst DPD of 30 or more. |
| Default | Worst DPD of 90 or more. |
| Early default | A 90+ DPD installment due within 6 months of issue. |
| Credit loss | 90% (loss given default) of the scheduled principal still owed when the loan first went 90 days late. Zero for seasoned loans that did not default. |
| Risk-adjusted LTV | LTV minus the credit loss per customer. |
| Active (funnel) | Any transaction other than the first deposit in days 31 to 90 after the first deposit. A withdrawal counts. |
| Attribution | Credit for a funded customer goes to the clicks before the first deposit: first touch, last touch, or position-based (40% first, 40% last, 20% shared by the middle clicks). A customer with no click is unattributed. |
| Wasteful campaign | A campaign with CAC at least twice the median campaign CAC of its channel and spend of at least 2,000 EUR. |

## 3. Modeling assumptions

1. **Revenue and cost parameters** come from the assumptions table: interchange 0.30% of card spend, origination fee 3% of principal, cost of funds 4.5% a year on the scheduled outstanding principal, servicing 0.40 EUR per active customer-month, KYC 2.50 EUR per check, loss given default 90%.
2. **Loan interest is rebuilt from the loan schedule.** The repayments table has no interest column, so the interest of each installment is calculated from the fixed-installment schedule and counted in the month it was paid. An unpaid installment earns nothing, and a partial payment earns its share.
3. **Servicing applies only in active months:** months with at least one transaction of any type.
4. **Response curve:** customers per month = a x monthly spend^b, fitted on the logs of 24 monthly points per channel. Customers are credited with the position-based model, in the month of the first deposit.
5. **Optimizer:** it maximises net profit (customers x net value per customer - ad spend). The budget is the July to September 2026 spend, used as a ceiling. Each channel stays between 50% and 150% of its baseline, referral at most 120%.
6. **Paid social curve:** the months of the Summer Reach campaign (June to September 2026) are left out of its fit by default. A switch on the `Assumptions` sheet turns this off.

## 4. Limitations

**Synthetic data**
- The data is generated, so the findings describe this simulation, not real customers. Default behaviour is an assumption, which makes the credit results the most uncertain part.

**Time span and cohorts**
- Two years of data. LTV and payback use only the customers funded at least 12 months before the extract date (2,780 of 5,928), so they describe the earlier customers.
- Credit loss per customer comes from the same early customers, whose loans have had time to default. Applying it to new customers assumes the same behaviour.

**Credit loss against LTV**
- The credit loss covers the whole life of a loan, while LTV covers 12 months. Interest earned after month 12 (about 44 to 69 EUR per customer) is not counted, so the risk-adjusted LTV is conservative. The `Assumptions` sheet has an input to test it.
- Loans issued after 2026-03-31 carry no credit loss, so the loss is a floor. 703 of the 2,290 loans are not yet seasoned.
- Cells with fewer than 50 seasoned loans are marked low sample and should not be read as findings.

**Response curves**
- Each curve has 24 monthly points, and the fits are rough (R squared 0.25 to 0.70). The paid social curve over-predicts at its baseline spend (74 customers a month against 40 won), which is the effect of the Summer Reach campaign.
- The curves treat channels as independent. They do not capture interaction between channels or a delay between spend and customers.

**Attribution**
- Only clicks count. Impressions earn no credit. The first-touch, last-touch and position-based models are conventions, not measurements of what caused a signup.

**Other**
- 378 customers have no segment and are labelled unknown.
- Deposit margin is not modeled, because the data has no balances.

**Left out on purpose**
- **Retention by channel and RFM segmentation** were in the first plan and are not part of this project. The retail project already covers cohort retention, churn and RFM with K-Means, and this project answers a different question: which channels bring profitable customers. RFM would also need clustering in Python, which is out of scope here.
- A quick check on the reporting views suggests that retention differs by channel: about 9% of paid social customers and 11% of affiliate customers still have a transaction in month 12, against 44% for referral. This is not analysed further here, and it would be the first thing to add.

## 5. What the analysis does not claim

- It does not claim these numbers describe a real bank or real customers.
- It does not claim that reallocating the budget will produce the modelled uplift. The uplift is a model estimate, and the recommendation is a hypothesis that has not been tested.
- It does not claim that channels cause the differences in credit risk. It shows which channels brought customers who later defaulted, in this dataset.
- It does not claim that the best allocation fixes profitability. Most of the loss comes from loan losses, which marketing spend cannot change.
