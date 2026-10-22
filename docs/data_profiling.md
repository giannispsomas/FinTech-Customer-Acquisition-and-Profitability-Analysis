# Data Profiling

## Overview

- **Data:** synthetic, for a fictional bank (Meltemi Bank). Generated with Python using a fixed seed.
- **Size:** 10 tables, 136,098 rows, October 2024 to September 2026. The extract date is 2026-09-30.
- **Tool:** SQL Server. The raw tables stay in schema `dbo` and are never changed.
- **Purpose:** find what is wrong with the raw tables before cleaning them, and decide what to do about each problem.
- **Script:** [sql/01_data_profiling.sql](../sql/01_data_profiling.sql), one section per table plus the cross-table checks.

The raw layer contains data quality problems, so I profiled all 10 tables before trusting any of them.

## Method

Every check has an ID made of a table prefix and a number (`CUS-08`, `TXN-11`, `XT-04`). Each one is a question, a query and a result. There are 93 checks in total.

| Prefix | Table |
|---|---|
| CHA | channels |
| CAM | campaigns |
| ADS | daily_ad_spend |
| CUS | customers |
| TOU | touchpoints |
| ACC | accounts |
| TXN | transactions |
| LOA | loans |
| REP | repayments |
| ASM | assumptions |
| XT | cross-table |

For each table I ran the same kinds of checks: row count, key uniqueness, NULLs and blanks, allowed values, number and date ranges, and links to parent tables. Then the cross-table checks looked at the order of events per customer.

The problems I found went into a triage table. For each one I decided whether it is wrong, expected or fine, which metric it affects, and what to do:

- **Fix:** change the value in the clean layer and keep the original beside it.
- **Exclude:** leave the rows out of the clean layer.
- **Flag:** keep the rows and add a flag column.
- **Keep as is:** no change.

I only investigated a finding further when the answer could change the decision.

## Load check

All 10 tables loaded with the expected number of rows.

| Table | Expected | Loaded |
|---|---|---|
| channels | 5 | 5 |
| campaigns | 25 | 25 |
| daily_ad_spend | 8,747 | 8,747 |
| customers | 10,100 | 10,100 |
| touchpoints | 21,019 | 21,019 |
| accounts | 9,806 | 9,806 |
| transactions | 64,908 | 64,908 |
| loans | 2,290 | 2,290 |
| repayments | 19,190 | 19,190 |
| assumptions | 8 | 8 |
| **Total** | **136,098** | **136,098** |

## Summary of issues

| Table | Main issues found | Triage | How cleaning handled it (see [data_cleaning.md](data_cleaning.md)) |
|---|---|---|---|
| customers | 60 exact copies, 40 uppercase re-signups, 15 spellings of 5 channels plus 8 odd names, 383 missing segments, 237 decisions with no KYC date | T-01 to T-07 | Duplicates left out, channels tidied and mapped, missing segment labelled `unknown`, KYC date flagged |
| touchpoints | 2,586 touches on the signup day | T-08 | Flag |
| accounts | 1,525 customers with two accounts | T-09 | Kept, counted by distinct customer |
| transactions | 323 negative amounts, 1,069 card payments with no category, 389 dated before the account opened, 41 amounts above 10,000 | T-10 to T-13, T-18 | Sign fixed, category labelled, three flags |
| daily_ad_spend | 122 rows with zero impressions | T-14 | Flag |
| assumptions | Float noise, a date stored as a number | T-15 | Rounded, date column, unit column |
| loans and repayments | 29 loans with no installments yet, loans too young to judge | T-16 | `window_complete` flag on loans |
| cross-table | 2,353 customers with an account and no deposit | T-17 | Flag in the reporting layer |
| channels, campaigns | Nothing found | | Straight copy |

## Findings by table

### customers (10,100 rows)

- **Keys:** 10,040 distinct `customer_id` values, so 60 ids appear twice. All 60 are exact copies.
- **Emails:** 100 emails appear twice. 60 are the exact copies. The other 40 are re-signups: the email is in uppercase, the `customer_id` is new (200001 to 200040), the signup is one day later, and the record has no touchpoints and no account. A `LIKE '%@example.com'` test misses them because the default collation ignores case.
- **Channel:** `acquisition_channel` is free text. It has 15 distinct values ignoring case, 23 case-sensitive, and 256 rows with stray spaces. After tidying, 8 names are still not one of the five channels: `ppc`, `sem`, `fb/ig_ads`, `social_paid`, `aff_network`, `affiliates`, `direct/organic`, `friend_referral`.
- **Segment:** 383 rows have no segment.
- **KYC:** `kyc_date` is empty on 1,393 rows. 1,156 are pending, which is expected. 226 verified and 11 rejected customers have a decision and no date.
- **Fine:** signup and KYC dates are inside the window, no KYC date is before the signup, countries are 8 valid codes.

### touchpoints (21,019 rows)

- No duplicates, no NULLs, no orphans, all dates inside the window.
- 18,348 clicks and 2,671 impressions.
- 2,586 touches fall on the customer's signup day. None fall after it. The signup date has no time, so a same-day touch cannot be placed before or after the signup.

### accounts (9,806 rows)

- Clean on every check. All account holders are verified, and no account opens before the signup or the KYC date.
- 1,525 customers have two accounts, which matches the 1,525 savings accounts (a current account plus a savings account). This is expected.

### transactions (64,908 rows)

- **Negative amounts:** 323, in every transaction type. Their average size is close to the positive rows of the same type, so they look like sign flips and not refunds.
- **Missing category:** `merchant_category` is empty on 30,325 rows. 29,256 are not card payments, which is expected. 1,069 are card payments with no category.
- **Early transactions:** 389 transactions are dated before their account opened, 5 of them before the window starts (the earliest is 2024-09-21). About 97 percent are 3 days or more early.
- **Large amounts:** the median is 85, the 99th percentile is about 2,061, and the maximum is 379,178. 41 amounts are above 10,000 and 8 deposits are above 100,000.

### daily_ad_spend (8,747 rows)

- Clean on keys, NULLs, dates and orphans. No organic campaign has spend rows.
- 122 rows have zero impressions and 127 have zero clicks. The money was still spent.

### loans (2,290 rows) and repayments (19,190 rows)

- Both are clean on keys, ranges and links.
- Installments exist only up to the extract date, so recent loans have fewer installments than their term. 29 loans issued between 2026-09-01 and 2026-09-10 have none yet.
- 9,916 installments were paid before the due date. That is normal, and it means days past due can be negative.

### assumptions (8 rows)

- `assumption_value` is a float. Six values carry noise, for example 0.3 percent is stored as 0.00300000002607703. The column also mixes rates, euro amounts and a date, and the extract date is stored as the number 20260930.

### channels and campaigns

- Nothing wrong. Names, dates and links all check out.

### Cross-table

- **Orphans:** none on any of the 8 links.
- **Order of events:** 81 customers have their first deposit before their first account.
- **Deposits:** only 5,928 of the 8,281 customers with an account ever made a deposit. None of the 2,353 without a deposit has a loan.
- **Channel:** the recorded channel and the channel of the first ad differ for about 5 to 8 percent of customers, in every channel, including the clean names. This is the normal gap between where a customer is recorded and which ad they saw first. It matters for the attribution question.

## Triage

| ID | Table | Finding | Decision |
|---|---|---|---|
| T-01 | customers | 60 repeated ids, all exact copies | Exclude |
| T-02 | customers | 100 repeated emails: 60 copies and 40 uppercase re-signups | Exclude |
| T-03 | customers | Channel case variants and 256 rows with stray spaces | Fix |
| T-04 | customers | 8 odd channel names, 1,059 customers | Fix |
| T-05 | customers | 383 missing segments | Flag |
| T-06 | customers | 237 verified or rejected customers with no KYC date | Flag |
| T-07 | customers | 40 customers with no touchpoint, the same 40 re-signups | Exclude |
| T-08 | touchpoints | 2,586 touches on the signup day | Flag |
| T-09 | accounts | 1,525 customers with two accounts | Keep as is |
| T-10 | transactions | 323 negative amounts | Fix |
| T-11 | transactions | 1,069 card payments with no category | Flag |
| T-12 | transactions | 389 transactions dated before the account opened | Flag |
| T-13 | transactions | 5 transactions before the window starts | Flag |
| T-14 | daily_ad_spend | 122 rows with zero impressions | Flag |
| T-15 | assumptions | Float noise and a date stored as a number | Fix |
| T-16 | loans, repayments | 29 loans with no installments yet | Flag |
| T-17 | cross-table | 2,353 customers with an account and no deposit | Flag |
| T-18 | transactions | 41 amounts above 10,000, up to 379,178 | Flag |

## Key takeaways

1. The default SQL Server collation ignores case, so `GROUP BY` merges `Paid Social` and `paid_social`. To see the variants, group with `COLLATE Latin1_General_CS_AS`.
2. `count(*)`, `count(column)` and `count(distinct column)` give different numbers. The gaps between them are findings.
3. A join to a table with repeated ids multiplies rows. Count with `count(distinct ...)` or collapse the table to one row per id first.
4. A comparison with NULL gives no answer, so the row drops out without any warning. The loan customers with no deposit were invisible to the date-order check until I counted them separately.
5. For a datetime column, test the upper end with `>= next day`, not `> last day`.
6. Look for problems in the direction of the join. An orphan check starts from the child table.
7. A heavy tail in money amounts is not an error by itself. I flagged the large amounts and decided to test their effect in the analysis.
