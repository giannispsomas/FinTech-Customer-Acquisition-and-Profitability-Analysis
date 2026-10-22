# Reporting Views

## Overview

- **Source:** the cleaned tables in schema `clean` (see [data_cleaning.md](data_cleaning.md)).
- **Output:** ten views in schema `rpt`. Every metric is defined once here, and the EDA, the Excel model and the Power BI report all read from these views.
- **Tool:** SQL Server, one script: [sql/03_reporting_views.sql](../sql/03_reporting_views.sql), one step per view.
- **Design:** no star schema. The project is about marketing analytics, so the operational tables stay as they are and the views sit on top of them.
- **Re-running:** every view is created with `create or alter`, so the script is safe to run again. The views use each other, so the steps must run in order.

## The views

| Step | View | One row per | Rows | Used by |
|---|---|---|---|---|
| 01 | `v_funded_customers` | funded customer | 5,928 | almost every other view |
| 02 | `v_customer_month_margin` | funded customer per 30-day month (1 to 12) | 71,136 | the curve and the scorecard |
| 03 | `v_funnel` | customer | 10,000 | Q1 |
| 04 | `v_loan_dpd` | loan | 2,290 | Q5, the scorecard |
| 05 | `v_touch_credit` | funded customer per qualifying click, plus unattributed | 10,690 | Q3, campaigns, budget inputs |
| 06 | `v_channel_curve` | channel per month since first deposit | 60 | the scorecard, the payback chart |
| 07 | `v_channel_scorecard` | channel | 5 | Q2, Q5, budget inputs |
| 08 | `v_credit_by_segment` | channel and segment | 25 | Q5 |
| 09 | `v_campaign_cac` | campaign | 25 | Q4 |
| 10 | `v_budget_inputs` | paid channel per month | 96 | the Excel model |

The grain, columns and rules of each view are written in the header of its step in the script.

## Key design decisions

### Funded customers (step 01)
A customer is acquired when they make a first deposit. The first deposit date ignores deposits dated before the account opened (389 transactions have that problem). No customer is lost by this, because every customer with such a deposit also has a clean one.

### Margin by month (step 02)
This is the largest view. For each funded customer and each of the first 12 months it adds up the five money amounts:

- **Interchange:** 0.30% of card spend.
- **Origination fee:** 3% of the principal, in the month the loan is issued.
- **Loan interest:** rebuilt from the loan schedule, because the repayments table has no interest column. The installment amount in the data matches the standard fixed-installment formula on all 2,261 loans that have installments.
- **Cost of funds:** 4.5% a year on the principal still owed, in the month the installment is due.
- **Servicing:** 0.40 EUR in every month with at least one transaction.

A month with no activity has no source row, so the view builds a grid of every customer and every month first and fills the gaps with zeros. Without it, averages over months would only count the active months. The column `month_complete` marks months that the data fully covers, so late months are not dragged down by customers who have not had time to reach them.

### Credit (steps 04 and 08)
Days past due are calculated per installment and then summarised per loan. The default flags and the credit loss are only filled for seasoned loans, so recent loans do not flatter the channels with recent lending. Unseasoned loans keep NULL, and they stay in loan counts and in revenue.

### Attribution (step 05)
Only clicks before the first deposit moment count. The view holds the three ways of giving credit side by side (first touch, last touch, position-based), so they can be compared without recalculating. Each credit column adds up to the 5,928 funded customers, which is the reconciliation check.

### Scorecard (step 07)
CAC, LTV, LTV/CAC, ROAS and payback per channel, before and after credit loss. Organic has no ad spend, so its CAC, ROAS and payback are NULL.

## Validation

| Check | Result |
|---|---|
| Funded customers | 5,928 rows, one per customer, no NULL first deposit date |
| Margin grid | 71,136 rows = 5,928 customers x 12 months, no duplicate customer-month |
| Interchange | the view total equals the direct sum of card spend x 0.30% |
| Origination fee | the view total (338,052) equals the direct sum of principal x 3% |
| Servicing | 11,056 = 27,640 active customer-months x 0.40 |
| Loan interest | on the 635 loans with a full schedule, the rebuilt interest equals installments x amount due - principal (difference 16 EUR in total) |
| Funnel | 10,000 customers, 8,281 verified, 5,928 funded, no active customer who is not funded |
| Loan DPD | 2,290 loans, 1,587 seasoned, flags only on seasoned loans, no default without a loss |
| Attribution | each credit column adds up to 5,928 |
| Campaigns | 25 campaigns, spend adds up to 152,050.93, the total of `daily_ad_spend` |
| Budget inputs | 96 rows (4 channels x 24 months), spend adds up to the same total |

## Lessons

1. **A row that does not exist cannot be averaged.** A month with no activity has no row, so it has to be created before any average over months.
2. **A fair average needs complete periods.** A customer funded two weeks before the extract date has not had 12 months, so each month number is averaged over the customers who reached it, and the number behind each point is kept.
3. **A date without a time hides the order of events.** The first deposit date has no time, so for attribution the view takes the timestamp of the first deposit to decide which clicks came before it.
4. **A column that is not in the data can be rebuilt, and then checked.** Loan interest was rebuilt from the schedule and checked against loans that had a full schedule, where the answer is known.
5. **A view must be the first statement of its batch.** Each `create or alter view` is followed by `go`, so the script can run in one go.
