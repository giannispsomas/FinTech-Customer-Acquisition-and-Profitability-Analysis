# DAX Measures

All measures live in the `_Measures` table, an empty table that holds only measures. The "Check" lines give the numbers the SQL views and the Excel model produce, so each measure can be tested against them.

**Table names in the model**

| Model name | Source |
|---|---|
| `dim channel` | `clean.channels` (5 rows, the one dimension, used by every slicer and axis) |
| `rpt v_funnel` | `rpt.v_funnel` (one row per customer, 10,000 rows) |
| `rpt v_loan_dpd` | `rpt.v_loan_dpd` (one row per loan, 2,290 rows) |
| `rpt v_touch_credit` | `rpt.v_touch_credit` (one row per funded customer per qualifying click, 10,690 rows) |
| `rpt v_channel_curve` | `rpt.v_channel_curve` (channel by month since first deposit, 60 rows) |
| `rpt v_channel_scorecard` | `rpt.v_channel_scorecard` (one row per channel, 5 rows) |
| `rpt v_credit_by_segment` | `rpt.v_credit_by_segment` (channel by segment, 25 rows) |
| `rpt v_campaign_cac` | `rpt.v_campaign_cac` (one row per campaign, 25 rows) |
| `rpt v_budget_inputs` | `rpt.v_budget_inputs` (paid channel by month, 96 rows) |
| `tblAllocation` | Excel model, sheet `Optimizer`: baseline and recommended spend per channel |
| `tblScenarios` | Excel model, sheet `Scenarios`: the eight scenarios |

`rpt.v_funded_customers` and `rpt.v_customer_month_margin` are not loaded. The scorecard and the curve already hold their results, and the margin view has 71,136 rows the report does not need.

**Relationships:** `dim channel[channel_name]` to the channel column of every other table (many to one, single direction): `acquisition_channel` in the scorecard, funnel, loan, curve and segment views; `channel_name` in the campaign and budget views; `touch_channel` in the touch credit view; `Channel` in `tblAllocation`. `tblScenarios` stands alone.

**Organic:** it has no ad spend, so CAC, ROAS, LTV/CAC and payback are blank for it.

**Excel columns:** the long Excel headers are renamed in Power Query: `Baseline Spend`, `Recommended Spend`, `Value Baseline` and `Value Recommended`.

## Contents

1. [Executive page](#1-executive-page)
2. [Funnel page](#2-funnel-page)
3. [Attribution and campaigns page](#3-attribution-and-campaigns-page)
4. [Credit risk page](#4-credit-risk-page)
5. [Budget scenarios page](#5-budget-scenarios-page)
6. [KPI scorecard page](#6-kpi-scorecard-page)
7. [Calculated columns](#7-calculated-columns)

---

## 1. Executive page

### Funded Customers
```DAX
Funded Customers =
SUM ( 'rpt v_channel_scorecard'[funded_customers] )
```
Check: 5,928. Used in: KPI card. Feeds `CAC` and `Credit Shift %`.

### Signups
```DAX
Signups =
DISTINCTCOUNT ( 'rpt v_funnel'[customer_id] )
```
Check: 10,000. Used in: the funnel table and `Verified Rate`.

### Ad Spend and KYC Cost
```DAX
Ad Spend =
SUM ( 'rpt v_channel_scorecard'[ad_spend] )

KYC Cost =
SUM ( 'rpt v_channel_scorecard'[kyc_cost] )
```
Check: 152,051 of ad spend. Both feed `CAC` and `Attributed CAC`.

### CAC
Cost to acquire one funded customer: ad spend plus KYC cost, divided by funded customers. Blank for organic.
```DAX
CAC =
VAR _spend = [Ad Spend]
RETURN
    IF ( _spend = 0, BLANK (), DIVIDE ( _spend + [KYC Cost], [Funded Customers] ) )
```
Check: referral 12.47, affiliate 32.03, paid search 32.94, paid social 65.59. Used in: scorecard table, attribution table.

### Blended CAC
CAC over the four paid channels together. Used for the KPI card, because the grand total of `CAC` would include organic customers.
```DAX
Blended CAC =
CALCULATE ( [CAC], 'dim channel'[channel_name] <> "organic" )
```
Check: 37.49.

### LTV 12m
Average cumulative margin per customer at month 12, weighted by the number of customers behind each channel's figure.
```DAX
LTV 12m =
DIVIDE (
    SUMX (
        'rpt v_channel_scorecard',
        'rpt v_channel_scorecard'[ltv_12m] * 'rpt v_channel_scorecard'[eligible_customers_12m]
    ),
    SUM ( 'rpt v_channel_scorecard'[eligible_customers_12m] )
)
```
Check: affiliate 251.54, paid search 185.36, paid social 171.28, organic 167.97, referral 165.36; all channels together 184.18. Used in: KPI card, scorecard table, the credit risk bar chart.

### Risk-adjusted LTV
12-month LTV minus the credit loss per customer, weighted the same way.
```DAX
Risk-adjusted LTV =
DIVIDE (
    SUMX (
        'rpt v_channel_scorecard',
        'rpt v_channel_scorecard'[risk_adj_ltv_12m] * 'rpt v_channel_scorecard'[eligible_customers_12m]
    ),
    SUM ( 'rpt v_channel_scorecard'[eligible_customers_12m] )
)
```
Check: affiliate -490.95, paid search -31.96, paid social -54.03, organic -28.24, referral +54.49; all channels together -84.10.

### LTV to CAC
```DAX
LTV to CAC =
DIVIDE ( [LTV 12m], [CAC] )
```
Check: referral 13.3, affiliate 7.9, paid search 5.6, paid social 2.6.

### Revenue 12m and ROAS
Gross revenue per euro of ad spend (ad spend only, without KYC cost).
```DAX
Revenue 12m =
DIVIDE (
    SUMX (
        'rpt v_channel_scorecard',
        'rpt v_channel_scorecard'[revenue_12m] * 'rpt v_channel_scorecard'[eligible_customers_12m]
    ),
    SUM ( 'rpt v_channel_scorecard'[eligible_customers_12m] )
)

ROAS =
DIVIDE ( [Revenue 12m], DIVIDE ( [Ad Spend], [Funded Customers] ) )
```
Check, ROAS: referral 22.7, affiliate 11.5, paid search 8.0, paid social 3.6.

### Payback Month
First month where the average cumulative margin reaches CAC. Blank when more than one channel is selected, and for organic.
```DAX
Payback Month =
IF (
    HASONEVALUE ( 'dim channel'[channel_name] ),
    MAX ( 'rpt v_channel_scorecard'[payback_month] ),
    BLANK ()
)
```
Check: referral 2, affiliate 3, paid search 4, paid social 6.

### Cumulative Margin per Customer
```DAX
Cumulative Margin per Customer =
AVERAGE ( 'rpt v_channel_curve'[avg_cum_margin] )
```
Used in: the payback line (month on the axis, one line per channel). Check at month 12: affiliate 251.54, referral 165.36.

### Baseline Spend and Recommended Spend
```DAX
Baseline Spend =
SUM ( tblAllocation[Baseline Spend] )

Recommended Spend =
SUM ( tblAllocation[Recommended Spend] )
```
Check: 28,603 and 15,058 in total. Used in: the spend bar chart.

### Spend Change %
```DAX
Spend Change % =
DIVIDE ( [Recommended Spend] - [Baseline Spend], [Baseline Spend] )
```
Check: -50% for affiliate, paid search and paid social; +20% for referral. Not used in a visual (the Excel table already has the column).

### Net Profit at Baseline Spend, Net Profit at Recommended Spend and Uplift
```DAX
Net Profit at Baseline Spend =
SUM ( tblAllocation[Value Baseline] ) - SUM ( tblAllocation[Baseline Spend] )

Net Profit at Recommended Spend =
SUM ( tblAllocation[Value Recommended] ) - SUM ( tblAllocation[Recommended Spend] )

Uplift =
[Net Profit at Recommended Spend] - [Net Profit at Baseline Spend]
```
Check: -97,564, -56,843 and 40,720. Used in: the Uplift KPI card.

---

## 2. Funnel page

### Verified, Funded in Funnel, Active
```DAX
Verified =
SUM ( 'rpt v_funnel'[is_verified] )

Funded in Funnel =
SUM ( 'rpt v_funnel'[is_funded] )

Active =
SUM ( 'rpt v_funnel'[is_active] )
```
Check: 8,281 verified, 5,928 funded, 4,551 active. Used in: the counts table.

### Verified Rate
```DAX
Verified Rate =
DIVIDE ( [Verified], [Signups] )
```
Check: affiliate 69.5%, paid social 80.1%, paid search 87.0%, organic 88.0%, referral 92.5%.

### Verified to Funded
Only customers who signed up at least 30 days before the extract date are counted, because later signups have not had time to fund.
```DAX
Verified to Funded =
DIVIDE (
    CALCULATE (
        SUM ( 'rpt v_funnel'[is_funded] ),
        'rpt v_funnel'[funded_rate_eligible] = 1,
        'rpt v_funnel'[is_verified] = 1
    ),
    CALCULATE (
        SUM ( 'rpt v_funnel'[is_verified] ),
        'rpt v_funnel'[funded_rate_eligible] = 1
    )
)
```
Check: paid social 52.4%, affiliate 71.8%, paid search 78.9%, organic 81.4%, referral 88.9%. By segment: student 63.0%, freelancer 67.2%, salaried 80.4%.

### Funded to Active
Only customers funded at least 90 days before the extract date are counted.
```DAX
Funded to Active =
DIVIDE (
    CALCULATE (
        SUM ( 'rpt v_funnel'[is_active] ),
        'rpt v_funnel'[active_rate_eligible] = 1
    ),
    CALCULATE (
        SUM ( 'rpt v_funnel'[is_funded] ),
        'rpt v_funnel'[active_rate_eligible] = 1
    )
)
```
Check: affiliate 74.8%, paid social 74.1%, organic 84.3%, paid search 86.7%, referral 89.6%.

---

## 3. Attribution and campaigns page

### First-Touch, Last-Touch and Position-Based Customers
```DAX
First-Touch Customers =
SUM ( 'rpt v_touch_credit'[credit_first_touch] )

Last-Touch Customers =
SUM ( 'rpt v_touch_credit'[credit_last_touch] )

Position-Based Customers =
SUM ( 'rpt v_touch_credit'[credit_position] )
```
Check, position-based: paid search 1,892, paid social 981, affiliate 849, referral 863, organic 1,342. One customer with no click is credited to `unattributed`, which is not in `dim channel`, so the five channels add up to 5,927.

### Credit Shift %
The recorded channel is the channel stored at signup, which is the same number as `Funded Customers`.
```DAX
Credit Shift % =
DIVIDE ( [Position-Based Customers] - [Funded Customers], [Funded Customers] )
```
Check: paid search +22.5%, paid social -19.9%, affiliate +0.4%, referral -5.3%, organic -4.2%.

### Attributed CAC
CAC recalculated on the position-based credit. Blank for organic.
```DAX
Attributed CAC =
IF (
    [Ad Spend] = 0,
    BLANK (),
    DIVIDE ( [Ad Spend] + [KYC Cost], [Position-Based Customers] )
)
```
Check: paid social 81.87, paid search 26.90, affiliate 31.92, referral 13.17.

### Campaign Spend, Credited Customers and Campaign CAC
```DAX
Campaign Spend =
SUM ( 'rpt v_campaign_cac'[total_spend] )

Credited Customers =
SUM ( 'rpt v_campaign_cac'[credited_customers] )

Campaign CAC =
IF (
    [Credited Customers] = 0,
    BLANK (),
    DIVIDE ( [Campaign Spend], [Credited Customers] )
)
```
Check: 152,051 of spend; SO_Summer_Reach_2026 has a campaign CAC of 365.40, the next campaign 72.64. The bar chart shows the top 10.

### Channel Median CAC
```DAX
Channel Median CAC =
MAX ( 'rpt v_campaign_cac'[channel_median_cac] )
```
The median is calculated in SQL. Check: paid social 62.20. Not used in a visual.

### Cost per Customer
```DAX
Cost per Customer =
DIVIDE (
    SUM ( 'rpt v_budget_inputs'[ad_spend] ),
    SUM ( 'rpt v_budget_inputs'[credited_customers] )
)
```
Check: paid social 158.02 in 2026-Q3, between 46.84 and 90.88 in earlier quarters.

---

## 4. Credit risk page

### Seasoned Loans, Default Rate, Delinquency Rate
```DAX
Seasoned Loans =
SUM ( 'rpt v_loan_dpd'[window_complete] )

Default Rate =
DIVIDE ( SUM ( 'rpt v_loan_dpd'[is_default_90] ), [Seasoned Loans] )

Delinquency Rate =
DIVIDE ( SUM ( 'rpt v_loan_dpd'[is_delinquent_30] ), [Seasoned Loans] )
```
Check: 1,587 seasoned loans and a default rate of 12.8% in total. Default rate by channel: affiliate 24.1%, paid social 12.5%, organic 11.3%, paid search 10.2%, referral 6.5%. Delinquency: affiliate 29.4%, paid social 18.1%, organic 15.7%, paid search 15.0%, referral 8.9%.

### Credit Loss
```DAX
Credit Loss =
SUM ( 'rpt v_loan_dpd'[credit_loss] )
```
Check: affiliate 325,882; paid search 162,493; organic 146,248; paid social 139,235; referral 68,045; 841,904 in total.

### Early Default Rate by Cell
For the heatmap (segment by channel). Built on the segment view so the low-sample flag matches the SQL.
```DAX
Early Default Rate by Cell =
DIVIDE (
    SUM ( 'rpt v_credit_by_segment'[early_default_loans] ),
    SUM ( 'rpt v_credit_by_segment'[seasoned_loans] )
)
```
Check: affiliate students 37.0%, affiliate young professionals 22.4%.

### Low Sample
Used for conditional formatting: cells with fewer than 50 seasoned loans are greyed.
```DAX
Low Sample =
IF ( SUM ( 'rpt v_credit_by_segment'[seasoned_loans] ) < 50, 1, 0 )
```

---

## 5. Budget scenarios page

This page uses the columns of `tblScenarios` directly and needs no measure: `Scenario`, `Total spend (EUR)`, `Customers won`, `Net profit at recommended spend (EUR)` and `Uplift (EUR)`. The values are the Solver results pasted into the Excel model.

## 6. KPI scorecard page

Targets are illustrative (there are no real company targets). Each target is a measure that holds one number, so it can be changed in one place.

```DAX
Target CAC = 40
Target LTV to CAC = 3
Target Payback Month = 6
Target Risk-adjusted LTV = 0
Target Default Rate = 0.10
Target Verified to Funded = 0.75
```

### Color measures
One per KPI. They return a color for the background of the cell: green if the KPI meets its target, red if not, white if the KPI has no value (organic has no CAC, LTV/CAC or payback). KPIs where lower is better (CAC, payback, default rate) use `<=`, the others `>=`.
```DAX
CAC Color =
IF ( ISBLANK ( [CAC] ), "#FFFFFF",
    IF ( [CAC] <= [Target CAC], "#C6E0B4", "#F8CBAD" ) )
```
`LTV to CAC Color`, `Payback Color`, `Risk-adjusted LTV Color`, `Default Rate Color` and `Verified to Funded Color` follow the same pattern with their own measure and target. They are applied in the table with Format visual, Cell elements, Background color, Field value.

### KPIs on Target, KPIs Measured and Scorecard Status
```DAX
KPIs on Target =
IF ( NOT ISBLANK ( [CAC] ) && [CAC] <= [Target CAC], 1, 0 )
+ IF ( NOT ISBLANK ( [LTV to CAC] ) && [LTV to CAC] >= [Target LTV to CAC], 1, 0 )
+ IF ( NOT ISBLANK ( [Payback Month] ) && [Payback Month] <= [Target Payback Month], 1, 0 )
+ IF ( NOT ISBLANK ( [Risk-adjusted LTV] ) && [Risk-adjusted LTV] >= [Target Risk-adjusted LTV], 1, 0 )
+ IF ( NOT ISBLANK ( [Default Rate] ) && [Default Rate] <= [Target Default Rate], 1, 0 )
+ IF ( NOT ISBLANK ( [Verified to Funded] ) && [Verified to Funded] >= [Target Verified to Funded], 1, 0 )

KPIs Measured =
IF ( NOT ISBLANK ( [CAC] ), 1, 0 )
+ IF ( NOT ISBLANK ( [LTV to CAC] ), 1, 0 )
+ IF ( NOT ISBLANK ( [Payback Month] ), 1, 0 )
+ IF ( NOT ISBLANK ( [Risk-adjusted LTV] ), 1, 0 )
+ IF ( NOT ISBLANK ( [Default Rate] ), 1, 0 )
+ IF ( NOT ISBLANK ( [Verified to Funded] ), 1, 0 )

Scorecard Status =
IF ( [KPIs Measured] = 0, BLANK (),
    [KPIs on Target] & " of " & [KPIs Measured] & " on target" )
```
Check: referral 6 of 6, paid search 4 of 6, affiliate 3 of 6, paid social 1 of 6, organic 1 of 3 (it has no CAC, LTV/CAC or payback). The page has 15 measures: 6 targets, 6 colors and these 3. The report has 56 measures in total.

## 7. Calculated columns

### Signup Quarter
Added to `rpt v_funnel`, used on the axis of the verified-to-funded line.
```DAX
Signup Quarter =
YEAR ( 'rpt v_funnel'[signup_date] )
    & "-Q"
    & QUOTIENT ( MONTH ( 'rpt v_funnel'[signup_date] ) - 1, 3 ) + 1
```

### Issue Quarter
Added to `rpt v_loan_dpd`, used on the axis of the default-rate line. The chart leaves out 2024-Q4 with a filter on that visual only, because that quarter has only 4 to 13 loans per channel.
```DAX
Issue Quarter =
YEAR ( 'rpt v_loan_dpd'[issue_date] )
    & "-Q"
    & QUOTIENT ( MONTH ( 'rpt v_loan_dpd'[issue_date] ) - 1, 3 ) + 1
```

### Quarter
Added to `rpt v_budget_inputs`, used on the axis of the cost-per-customer line.
```DAX
Quarter =
YEAR ( 'rpt v_budget_inputs'[month_start] )
    & "-Q"
    & QUOTIENT ( MONTH ( 'rpt v_budget_inputs'[month_start] ) - 1, 3 ) + 1
```
Check: eight quarters from 2024-Q4 to 2026-Q3.
