# Business Questions

This project answers one headline question through five supporting questions. The five are answered with SQL queries on the reporting views. The headline question is answered in the Excel model, using the results of the five.

**Headline question:** which acquisition channels bring profitable customers, and how should next quarter's marketing budget be reallocated?

**Currency:** all amounts are in EUR.
**Organic:** it has no ad spend, so it has no CAC, ROAS or payback. It is the unpaid baseline in the funnel, LTV and credit-risk comparisons.

## Contents

1. [SQL questions (Q1-Q5)](#1-sql-questions-q1-q5)
2. [The headline question, answered in Excel](#2-the-headline-question-answered-in-excel)
3. [Where each question is used](#3-where-each-question-is-used)

---

## 1. SQL questions (Q1-Q5)

All queries are in [`sql/04_business_questions.sql`](../sql/04_business_questions.sql). They run on the reporting views built in [`sql/03_reporting_views.sql`](../sql/03_reporting_views.sql). Q0 in that file is a warm-up: 10,000 signups, of which 5,928 funded. Paid social is the largest channel (2,917 signups) and referral the smallest (1,116).

### Q1. Where do we lose people, and does it differ by channel? (funnel)
- **Method:** `rpt.v_funnel` has one row per customer with a 0/1 flag per stage (signup, KYC verified, funded, active). Each rate uses only the customers who had enough time to reach the stage: signups on or before 2026-08-31 for the funded rate, first deposits on or before 2026-07-02 for the active rate.
- **Finding:** paid social loses most between verified and funded: only 52.4% of its verified customers fund, against 72% to 89% in the other channels. Affiliate loses at the KYC step: only 69.5% of its signups verify, against 80% to 92.5%. Referral is the best channel at every stage. Students (63.0%) and freelancers (67.2%) fund less often after verifying than salaried customers (80.4%), but paid social is lower than any segment. The time from signup to first deposit is about 8 days in every channel.
- **Used in:** page 2 (Funnel) of the Power BI report.

### Q2. Which channels earn back what we paid to win a customer, and how fast? (payback)
- **Method:** `rpt.v_channel_scorecard` and `rpt.v_channel_curve`. CAC is (ad spend + 2.50 EUR per KYC decision) divided by funded customers. LTV is the average cumulative margin per customer at month 12. Payback is the first month where the average cumulative margin reaches CAC. Month k uses only customers who have had k full months.
- **Finding:** before credit loss, every channel pays back within 12 months.

  | Channel | CAC | LTV (12 months) | LTV / CAC | Payback month |
  |---|---|---|---|---|
  | referral | 12.47 | 165.36 | 13.3 | 2 |
  | affiliate | 32.03 | 251.54 | 7.9 | 3 |
  | paid search | 32.94 | 185.36 | 5.6 | 4 |
  | paid social | 65.59 | 171.28 | 2.6 | 6 |

  The average hides the typical customer. The median 12-month margin is about 0 for organic (-0.13), paid social (-0.07) and referral (0.23), and about half of those customers have zero or negative margin. The averages are carried by customers with loans. The 41 very large card payments change the LTV by at most 0.19 and do not change the channel order. Affiliate has the highest margin in the salaried (271), young professional (293) and student (250) segments.
- **Used in:** the `Unit_Economics` sheet and the payback chart in the Excel model.

### Q3. Are we giving too much credit to some channel? (attribution)
- **Method:** `rpt.v_touch_credit` credits each funded customer to the channels of the clicks before their first deposit, in three ways: first touch, last touch, and position-based (40% first, 40% last, 20% shared by the middle clicks). Each model is compared with the recorded channel. Each model adds up to 5,928 customers, and one customer has no click.
- **Finding:** the recorded channel gives paid social too much credit and paid search too little. Paid social falls from 1,225 customers to 981 under position-based credit (-19.9%) and 897 under last touch (-26.8%). Paid search rises from 1,545 to 1,892 (+22.5%) and 2,137 (+38.3%). Affiliate (+0.4%), referral (-5.3%) and organic (-4.2%) barely move. Recalculated on position-based credit, paid social CAC rises from 65.59 to 81.87 and paid search CAC falls from 32.94 to 26.90, which makes paid search cheaper than affiliate (31.92). 80% of funded customers have one or two clicks before their first deposit.
- **Used in:** page 3 (Attribution and campaigns) of the Power BI report.

### Q4. Which campaigns waste money?
- **Method:** `rpt.v_campaign_cac`. A campaign is wasteful when its CAC is at least twice the median campaign CAC of its own channel and its spend is at least 2,000 EUR. Campaigns are only compared inside their channel.
- **Finding:** one campaign is flagged: SO_Summer_Reach_2026 (paid social, 1 June to 30 September 2026). Its CAC is 365.40 against a channel median of 62.20, so 5.9 times higher. It holds 18,124 of paid social's 73,973 spend (24.5%) and brought 49.6 customers. Every other campaign is between 0.86 and 1.25 times its channel median. Spend on days with zero impressions is small (about 2,000 in total, 1.3% of spend) and is not where the waste comes from. There is no clear November to December pattern in cost per customer. The real signal is paid social from June to September 2026, when the cost per customer was 144 to 201 against roughly 40 to 90 before.
- **Used in:** the `Pivot_Tables` sheet (cost per customer by quarter and channel), and the `Curves` and `Optimizer` sheets (the Summer Reach months are left out of the paid social curve by default).

### Q5. Which channels bring customers who do not repay? (credit risk)
- **Method:** `rpt.v_loan_dpd` and `rpt.v_credit_by_segment`. Rates use seasoned loans only (issued on or before 2026-03-31, 1,587 loans). A default is a worst days past due of 90 or more. Credit loss is 90% of the principal still owed when the loan first went 90 days late. Risk-adjusted LTV is the 12-month LTV minus the credit loss per customer.
- **Finding:** affiliate has by far the highest default rate: 24.1% of its seasoned loans, against 6.5% to 12.5% in the other channels, and the biggest credit loss (325,882). 49% of its loans are grade D to G (paid social 31%, organic 19%, paid search 18%, referral 10%). The problem is concentrated in students (37.0% early default on 108 loans) and young professionals (22.4% on 76); affiliate salaried customers are at 9.3%, in line with the other channels. After credit loss the 12-month value per customer is negative for affiliate (-490.95), paid social (-54.03), paid search (-31.96) and organic (-28.24). Only referral stays positive (+54.49). Affiliate goes from the best channel before credit loss (LTV/CAC 7.9) to the worst after it (-15.3). The share of loans too young to judge is similar in every channel (28% to 33%).
- **Used in:** the `Unit_Economics` and `Optimizer` sheets (risk-adjusted value per customer).

---

## 2. The headline question, answered in Excel

The model is in [`excel/budget_model.xlsx`](../excel/budget_model.xlsx). It fits a response curve per channel (customers = a x spend^b), takes the risk-adjusted value per customer from Q5, and uses Solver to find the spend per channel that maximises net profit. Each channel stays between 50% and 150% of its baseline (July to September 2026 spend), referral at most 120%, and the total stays within the baseline budget.

- **Finding:** the best allocation puts affiliate, paid search and paid social at their lower limit (50% of baseline) and referral at its upper limit (120%). Total spend falls from 28,603 to 15,058 per quarter. The quarter improves by about 40,700, but the net result is still negative (about -56,800), because loan losses dominate. The biggest lever is credit policy, not channel mix.
- **Scenarios:** the three channels stay at their lower limit when the budget changes by 20% and when credit losses change by 25%. Referral falls slightly below its baseline only when credit losses rise 25%.
- **Why a ceiling and not a fixed budget:** with a fixed budget, the model is forced to spend the whole amount, and it puts the money into paid social, the channel that wins the fewest customers per euro. That only looks better because it loses less per euro.

---

## 3. Where each question is used

| Question | Reporting views | Excel model |
|---|---|---|
| Q1 Funnel | `v_funnel` | not used |
| Q2 Payback | `v_customer_month_margin`, `v_channel_curve`, `v_channel_scorecard` | `Unit_Economics` |
| Q3 Attribution | `v_touch_credit` | position-based credit feeds the curves |
| Q4 Wasteful campaigns | `v_campaign_cac` | `Curves` (Summer Reach switch) |
| Q5 Credit risk | `v_loan_dpd`, `v_credit_by_segment`, `v_channel_scorecard` | `Unit_Economics`, `Optimizer` |
| Headline | `v_budget_inputs` | `Optimizer`, `Scenarios`, `Summary` |

## 4. Checks added after the first version

| Check | Question it answers | Where |
|---|---|---|
| Bootstrap intervals for CAC and LTV | Which channel differences are larger than chance? | [Statistical_Comparison.md](Statistical_Comparison.md) |
| Logistic regression on loan defaults | Why does affiliate default more: the channel or the loans it brings? | [Credit_Risk_Model.md](Credit_Risk_Model.md) |
| Optimizer re-run with channel values at the ends of their intervals | Does the recommended allocation survive the uncertainty? | [LTV_Scenarios.md](LTV_Scenarios.md) |
| KPI scorecard with targets | Which channels meet which targets, and how are the trends moving? | Page 6 of the Power BI report, [Report_Guide.md](Report_Guide.md) |
