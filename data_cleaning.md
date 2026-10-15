# Data Cleaning

## Overview

- **Source:** the raw tables in schema `dbo` (see [data_profiling.md](data_profiling.md)).
- **Output:** the cleaned tables in schema `clean`, one per raw table.
- **Tool:** SQL Server, one script per table in [sql/clean](sql/clean/).
- **Rules:** every rule comes from a triage decision (T-01 to T-18). The raw tables are only read, never changed.
- **Re-running:** each script drops and rebuilds its table, so it is safe to run again. Run them in number order, because `09_clean_transactions.sql` reads `clean.accounts`.
- **Pattern:** a fix keeps the original value beside the new one (`amount_raw`, `acquisition_channel_raw`). A flag is a 0/1 column. Rows are only left out when they are duplicates.

## Row count log

Only `customers` loses rows. Every other table keeps all of its rows.

| Step | Description | Rows before | Rows removed | Rows after | Notes |
|---|---|---|---|---|---|
| 1 | customers: remove exact copies (`select distinct`) | 10,100 | 60 | 10,040 | T-01 |
| 2 | customers: keep the original record of each email, ignoring case | 10,040 | 40 | 10,000 | T-02, T-07 |
| 3 | customers: tidy and map the channel names | 10,000 | 0 | 10,000 | T-03, T-04 |
| 4 | customers: label missing segments `unknown` | 10,000 | 0 | 10,000 | T-05 |
| 5 | customers: flag verified or rejected with no KYC date | 10,000 | 0 | 10,000 | T-06 |
| 6 | transactions: fix the sign, label the category, add 3 flags | 64,908 | 0 | 64,908 | T-10 to T-13, T-18 |
| 7 | touchpoints: flag touches on the signup day | 21,019 | 0 | 21,019 | T-08 |
| 8 | daily_ad_spend: flag zero impressions | 8,747 | 0 | 8,747 | T-14 |
| 9 | loans: flag seasoned loans | 2,290 | 0 | 2,290 | T-16 |
| 10 | assumptions: fix the numbers, add a date column and a unit | 8 | 0 | 8 | T-15 |
| 11 | channels, campaigns, accounts, repayments: straight copies | 5, 25, 9,806, 19,190 | 0 | same | |

## Table by table

### customers

The script is a chain of four steps, each one a CTE.

- **Exact copies (T-01):** `select distinct` keeps each identical row once. 60 rows go.
- **Re-signups (T-02, T-07):** I number each person's rows by `lower(email)`, earliest signup first, and keep number 1. The 40 uppercase re-signups go. They carry nothing the original record lacks, and they have no touchpoints or accounts. The result is 10,000 customers, and each of them has a touchpoint.
- **Channel (T-03, T-04):** the name is trimmed, lowercased, and spaces and dashes become underscores. Then a `case` maps the 8 odd names to the five channels (`ppc` and `sem` to `paid_search`, `fb/ig_ads` and `social_paid` to `paid_social`, `aff_network` and `affiliates` to `affiliate`, `direct/organic` to `organic`, `friend_referral` to `referral`). I checked the mapping against each customer's first touch: every odd name lands 92 to 97 percent in one channel, the same as the clean names do. The original text stays in `acquisition_channel_raw`.
- **Segment (T-05):** a missing segment becomes `unknown`. I never guess a segment. I first added a flag column as well, then dropped it, because the label already marks those rows. 378 rows remain after the duplicates are gone.
- **KYC date (T-06):** `kyc_date_missing = 1` for a verified or rejected customer with no date (237 rows). A pending customer with no date is expected, so it is not flagged. I never invent a date.

### transactions

No row is removed.

- **Sign (T-10):** `amount = abs(amount)`, the original is in `amount_raw`, and `amount_sign_corrected = 1` marks the 323 rows.
- **Category (T-11):** a card payment with no category becomes `unknown`, with `merchant_category_missing = 1` (1,069 rows). Other types keep NULL, which is expected.
- **Early (T-12, T-13):** `txn_before_account_open = 1` when the transaction date is earlier than the account's open date (389 rows). I do not change the amount or the date, because nothing tells me which of the two dates is wrong.
- **Large amounts (T-18):** `amount_outlier = 1` above 10,000 (41 rows). The value is not changed.

### touchpoints, daily_ad_spend, loans

Each is a copy with one flag column:

- `touchpoints.touch_on_signup_day` (2,586 rows). It needs the signup date from `customers`, which repeats 60 ids. The script collapses `customers` to one row per id first, so the join does not repeat touches.
- `daily_ad_spend.zero_impressions` (122 rows). The rows stay in spend and stay out of the click-through rate.
- `loans.window_complete`: 1 if the loan was issued on or before 2026-03-31 (1,587 loans), 0 otherwise (703 loans). Recent loans are too young to reach 90 days past due, so default rates use only the seasoned ones.

### assumptions

- The values are rounded to 4 decimals and stored as `decimal(10,4)`.
- The extract date, stored as `20260930`, becomes the date 2026-09-30 in its own column.
- A `unit` column says whether a row is a rate, an amount in euros or a date.
- I compared the 8 rows with the values in the project log.

### channels, campaigns, accounts, repayments

Straight copies. The scripts only check that the row counts match.

## Validation

Each script ends with checks. All of them passed.

| Check | Result |
|---|---|
| Row counts, every table | rows before and after match, except customers (10,100 and 10,000) |
| customers: one row per id | 10,000 rows, 10,000 distinct ids |
| customers: channels | exactly the five channels, adding up to 10,000 |
| Flag counts | 323 sign flips, 1,069 missing categories, 41 large amounts, 389 early transactions, 2,586 signup-day touches, 122 zero-impression rows, 237 KYC dates, 378 unknown segments |
| transactions: negatives left | 0 |
| loans: seasoned and not yet | 1,587 and 703 |
| assumptions | the 8 values match the project log |

## Lessons

1. **A join can repeat rows.** Joining `customers` to `touchpoints` without collapsing the repeated ids would have turned 21,019 touches into more. A row count check after the join catches it.
2. **Two ways to remove duplicates.** `select distinct` removes rows that are identical in every column. The re-signups were not identical (new id, later date, uppercase email), so they needed `row_number()` over the lowercase email.
3. **SQL Server reads a whole batch before it runs it.** When I re-ran a script that adds a column to a table that already existed, it failed with "Invalid column name" before dropping the old table. Putting `go` after the `drop table` makes it a separate batch and fixes it.
4. **`tch.*` and not `*`.** After a join, a bare `*` brings in the other table's columns too, and `select into` fails on the duplicate `customer_id`.
5. **Keep the original.** Every fixed column has its raw value beside it, so any decision can be checked or undone.
6. **Fewer columns can be better.** I dropped the `segment_missing` flag because the `unknown` label already says the same thing. Flags are only needed where the value stays unchanged, like `kyc_date`.
