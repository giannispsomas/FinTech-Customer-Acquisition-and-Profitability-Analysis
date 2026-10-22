/*
================================================================================
FINTECH CUSTOMER ACQUISITION AND PROFITABILITY ANALYSIS - DATA CLEANING
================================================================================
Purpose   : Turn the raw tables in schema dbo into analysis-ready tables in schema
            clean, one per raw table. The raw tables are never modified.

Structure : PART 1  Setup                           reset, schema
            PART 2  Straight copies                 steps 01-04
            PART 3  Fix and flag                    steps 05-10
            PART 4  Validation                      row count log

Design rules
    1. Every rule comes from a triage decision (T-01 to T-18, docs/data_profiling.md).
    2. A fix keeps the original value beside the new one (amount_raw,
       acquisition_channel_raw). A flag is a 0/1 column. Rows are only left out
       when they are duplicates.
    3. Nothing is guessed: a missing segment is labelled unknown, a missing date
       stays missing and is flagged.
    4. Every step ends with a check: a labelled row count, or a count that must
       match the expected number.

How to run
    Run the whole script once, top to bottom, with nothing selected (F5). The reset
    block drops and rebuilds everything the script creates, so it can be re-run at
    any time. The lines that contain only the word GO split the script into
    batches; do not remove them. If red error text appears on the Messages tab,
    stop and read it before running anything else.
================================================================================
*/

use NeobankGrowth;
go


/*
================================================================================
PART 1 - SETUP
================================================================================
*/

if schema_id('clean') is null exec('create schema clean');
go

-- RESET: drop everything this script creates. The raw tables are never dropped.
drop table if exists clean.channels;
drop table if exists clean.campaigns;
drop table if exists clean.accounts;
drop table if exists clean.repayments;
drop table if exists clean.daily_ad_spend;
drop table if exists clean.touchpoints;
drop table if exists clean.loans;
drop table if exists clean.assumptions;
drop table if exists clean.transactions;
drop table if exists clean.customers;
go


/*
================================================================================
PART 2 - STRAIGHT COPIES
================================================================================
Profiling found nothing to change in these four tables.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 01 | clean.channels: Straight copy                                (COPY)
--------------------------------------------------------------------------------
-- PROBLEM : none found (CHA-01 to CHA-04).
-- RULE    : straight copy.
-- OUTPUT  : clean.channels
-- EXPECT  : 5 rows.

select
    cha.channel_id,
    cha.channel_name,
    cha.has_spend
into clean.channels
from dbo.channels cha;

-- Checks (rows_before = rows_after)
select (select count(*) from dbo.channels)   as rows_before,
       (select count(*) from clean.channels) as rows_after;

--------------------------------------------------------------------------------
-- STEP 02 | clean.campaigns: Straight copy                               (COPY)
--------------------------------------------------------------------------------
-- PROBLEM : none found (CAM-01 to CAM-08).
-- RULE    : straight copy.
-- OUTPUT  : clean.campaigns
-- EXPECT  : 25 rows.

select
    cam.campaign_id,
    cam.channel_id,
    cam.campaign_name,
    cam.start_date,
    cam.end_date,
    cam.objective
into clean.campaigns
from dbo.campaigns cam;

-- Checks (rows_before = rows_after)
select (select count(*) from dbo.campaigns)   as rows_before,
       (select count(*) from clean.campaigns) as rows_after;

--------------------------------------------------------------------------------
-- STEP 03 | clean.accounts: Straight copy                                (COPY)
--------------------------------------------------------------------------------
-- PROBLEM : T-09: 1,525 customers have two accounts (current plus savings).
--           This is expected, not an error.
-- RULE    : straight copy. Customers are always counted with count(distinct
--           customer_id), never by counting accounts.
-- OUTPUT  : clean.accounts
-- EXPECT  : 9,806 rows.

select
    acc.account_id,
    acc.customer_id,
    acc.account_type,
    acc.open_date,
    acc.status,
    acc.close_date
into clean.accounts
from dbo.accounts acc;

-- Checks (rows_before = rows_after)
select (select count(*) from dbo.accounts)   as rows_before,
       (select count(*) from clean.accounts) as rows_after;

--------------------------------------------------------------------------------
-- STEP 04 | clean.repayments: Straight copy                              (COPY)
--------------------------------------------------------------------------------
-- PROBLEM : T-16 (loans with no installments yet) is handled on the loans side.
--           9,916 installments were paid before the due date, which is normal.
-- RULE    : straight copy. Days past due can be negative here; rpt.v_loan_dpd
--           floors it at 0.
-- OUTPUT  : clean.repayments
-- EXPECT  : 19,190 rows.

select
    rep.repayment_id,
    rep.loan_id,
    rep.installment_no,
    rep.due_date,
    rep.paid_date,
    rep.amount_due,
    rep.amount_paid
into clean.repayments
from dbo.repayments rep;

-- Checks (rows_before = rows_after)
select (select count(*) from dbo.repayments)   as rows_before,
       (select count(*) from clean.repayments) as rows_after;


/*
================================================================================
PART 3 - FIX AND FLAG
================================================================================
Every change is a fix with the original kept beside it, a 0/1 flag, or the removal
of a duplicate (customers only).
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 05 | clean.daily_ad_spend: Flag zero-impression spend             (FLAG)
--------------------------------------------------------------------------------
-- PROBLEM : T-14: 122 rows have zero impressions, but the money was still
--           spent.
-- RULE    : keep the rows (they stay in spend) and add zero_impressions = 1,
--           which keeps them out of click-through rates.
-- OUTPUT  : clean.daily_ad_spend
-- EXPECT  : 8,747 rows, 122 flagged.

select
    ads.spend_id,
    ads.campaign_id,
    ads.spend_date,
    ads.spend,
    ads.impressions,
    ads.clicks,
    case when ads.impressions = 0 then 1 else 0 end as zero_impressions  -- T-14
into clean.daily_ad_spend
from dbo.daily_ad_spend ads;

-- Checks
-- Rows: rows_before = rows_after
select (select count(*) from dbo.daily_ad_spend)   as rows_before,
       (select count(*) from clean.daily_ad_spend) as rows_after;

-- Flag: 122 rows
select sum(zero_impressions) as flagged_rows
from clean.daily_ad_spend;
go

--------------------------------------------------------------------------------
-- STEP 06 | clean.touchpoints: Flag touches on the signup day            (FLAG)
--------------------------------------------------------------------------------
-- PROBLEM : T-08: 2,586 touches fall on the customer's signup day. signup_date
--           has no time, so a same-day touch cannot be ordered against the
--           signup.
-- RULE    : add touch_on_signup_day = 1. The signup date comes from customers,
--           which repeats 60 ids, so customers is collapsed to one row per id
--           first (otherwise the join would repeat touches).
-- OUTPUT  : clean.touchpoints
-- EXPECT  : 21,019 rows, 2,586 flagged.

with signup as (
    -- one signup_date per customer: dbo.customers repeats 60 ids (exact copies), and a direct join would repeat their touches
    select cus.customer_id, min(cus.signup_date) as signup_date
    from dbo.customers cus
    group by cus.customer_id
)
select
    tch.*,  -- every column of touchpoints (tch.* and not *, which would also add the signup columns)
    case when cast(tch.touch_ts as date) = sg.signup_date then 1 else 0 end as touch_on_signup_day  -- T-08
into clean.touchpoints
from dbo.touchpoints tch
left join signup sg
    on tch.customer_id = sg.customer_id;

-- Checks
-- Rows: rows_before = rows_after (a larger number would mean the join repeated rows)
select (select count(*) from dbo.touchpoints)   as rows_before,
       (select count(*) from clean.touchpoints) as rows_after;

-- Flag: 2,586 rows
select sum(touch_on_signup_day) as flagged_rows
from clean.touchpoints;
go

--------------------------------------------------------------------------------
-- STEP 07 | clean.loans: Flag seasoned loans                             (FLAG)
--------------------------------------------------------------------------------
-- PROBLEM : T-16: recent loans are too young to reach 90 days past due, so they
--           would flatter the channels with recent lending.
-- RULE    : window_complete = 1 for loans issued on or before 2026-03-31
--           (seasoned), 0 for later loans. Unseasoned loans stay in loan
--           penetration, origination fee and cost of funds, and are skipped in
--           default, delinquency and credit-loss rates.
-- OUTPUT  : clean.loans
-- EXPECT  : 2,290 rows: 1,587 seasoned, 703 not yet.

select
    lns.loan_id,
    lns.customer_id,
    lns.issue_date,
    lns.principal,
    lns.apr,
    lns.term_months,
    lns.grade,
    case when lns.issue_date <= '2026-03-31' then 1 else 0 end as window_complete  -- T-16
into clean.loans
from dbo.loans lns;

-- Checks
-- Rows: rows_before = rows_after
select (select count(*) from dbo.loans)   as rows_before,
       (select count(*) from clean.loans) as rows_after;

-- Flag: seasoned (1) and not yet seasoned (0), 1,587 and 703
select window_complete, count(*) as loans
from clean.loans
group by window_complete;
go

--------------------------------------------------------------------------------
-- STEP 08 | clean.assumptions: Fix numbers, add date and unit             (FIX)
--------------------------------------------------------------------------------
-- PROBLEM : T-15: assumption_value is a float, so 6 values carry noise (0.3% is
--           stored as 0.00300000002607703). One column mixes rates, euro
--           amounts and a date, and the extract date is stored as the number
--           20260930.
-- RULE    : numbers rounded to 4 decimals and stored as decimal(10,4); the date
--           becomes a real date in its own column; a unit column says rate, EUR
--           or date.
-- OUTPUT  : clean.assumptions
-- EXPECT  : 8 rows.

select
    asm.assumption_key,

    -- number: float noise removed (the date row gets NULL here)
    case when asm.assumption_key = 'as_of_date_serial' then null else cast(round(asm.assumption_value, 4) as decimal(10, 4))
    end as assumption_value,

    -- date: number -> int -> text 'yyyymmdd' -> date (all other rows get NULL)
    case when asm.assumption_key = 'as_of_date_serial' then cast(cast(cast(asm.assumption_value as int) as char(8)) as date)
    end as assumption_date,

    -- unit: first five keys are rates, next two are EUR amounts, the last one is a date
    case when asm.assumption_key in ('interchange_rate', 'deposit_net_interest_margin_annual',
                                     'loan_cost_of_funds_annual', 'origination_fee_rate',
                                     'loss_given_default') then 'rate'
         when asm.assumption_key in ('kyc_cost_per_check', 'servicing_cost_per_active_month') then 'EUR'
         when asm.assumption_key = 'as_of_date_serial' then 'date'
    end as unit,

    asm.note
into clean.assumptions
from dbo.assumptions asm;

-- Checks
-- Rows: rows_before = rows_after (8 and 8)
select (select count(*) from dbo.assumptions)   as rows_before,
       (select count(*) from clean.assumptions) as rows_after;

-- Values, compared by eye. Expected:
--   rates  0.0030, 0.0150, 0.0450, 0.0300, 0.9000 | EUR 2.5000, 0.4000 | date 2026-09-30 (value NULL)
select *
from clean.assumptions;
go

--------------------------------------------------------------------------------
-- STEP 09 | clean.transactions: Fix sign, label category, flag early and large amounts  (FIX + FLAG)
--------------------------------------------------------------------------------
-- PROBLEM : T-10: 323 negative amounts (sign flips). T-11: 1,069 card payments
--           with no category. T-12, T-13: 389 transactions dated before their
--           account opened. T-18: 41 amounts above 10,000.
-- RULE    : amount = abs(amount) with the original in amount_raw and
--           amount_sign_corrected = 1; missing card category labelled unknown
--           with merchant_category_missing = 1; txn_before_account_open = 1;
--           amount_outlier = 1. No row is removed and no date or large amount
--           is changed.
-- OUTPUT  : clean.transactions (needs clean.accounts from step 03)
-- EXPECT  : 64,908 rows.

select
    trs.txn_id,
    trs.account_id,
    trs.txn_ts,
    trs.txn_type,

    -- T-10: amount without the wrong sign, original kept beside it
    abs(trs.amount) as amount,
    trs.amount as amount_raw,
    case when trs.amount < 0 then 1 else 0 end as amount_sign_corrected,

    -- T-11: a missing category on a card_spend becomes 'unknown'; other types keep NULL
    case when trs.txn_type = 'card_spend' and trs.merchant_category is null

    then 'unknown' else trs.merchant_category
    end as merchant_category,
    case when trs.txn_type = 'card_spend' and trs.merchant_category is null then 1 else 0
    end as merchant_category_missing,

    -- T-18: very large amounts are flagged, not changed
    case when abs(trs.amount) > 10000 then 1 else 0 end as amount_outlier,

    -- T-12, T-13: dated before the account opened (time cut off to compare with the open date)
    case when cast(trs.txn_ts as date) < acc.open_date then 1 else 0 end as txn_before_account_open
    into clean.transactions
    from dbo.transactions trs
    inner join clean.accounts acc
        on trs.account_id = acc.account_id;  -- one row per account_id, so no row is repeated

-- Checks
-- Rows: rows_before = rows_after (64,908)
select (select count(*) from dbo.transactions)   as rows_before,
       (select count(*) from clean.transactions) as rows_after;

-- Flags: 323, 1,069, 41, 389
select sum(amount_sign_corrected)    as sign_corrected,
       sum(merchant_category_missing) as merchant_missing,
       sum(amount_outlier)           as outliers,
       sum(txn_before_account_open)  as before_account_open
from clean.transactions;

-- No negative amount may be left
select count(*) as negative_amounts_left
from clean.transactions
where amount < 0;
go

--------------------------------------------------------------------------------
-- STEP 10 | clean.customers: Remove duplicates, tidy channels, label segment, flag KYC  (EXCLUDE + FIX + FLAG)
--------------------------------------------------------------------------------
-- PROBLEM : T-01: 60 exact copies. T-02, T-07: 40 uppercase re-signups. T-03,
--           T-04: channel spelling variants and 8 odd names. T-05: missing
--           segment. T-06: verified or rejected with no KYC date.
-- RULE    : keep each identical row once, then keep the original record per
--           email (ignoring case, earliest signup); tidy the channel and map
--           the 8 odd names to the 5 channels (original in
--           acquisition_channel_raw); missing segment labelled unknown;
--           kyc_date_missing = 1. A segment or a date is never guessed.
-- OUTPUT  : clean.customers
-- EXPECT  : 10,000 rows (10,100 before).

with distinct_rows as (
    -- T-01: exact copies removed (10,100 -> 10,040)
    select distinct *
    from dbo.customers cus
),
numbered as (
    -- T-02, T-07: number each person's rows (same email in lower case), earliest signup first,
    -- lowest customer_id breaks a tie
    select
        dr.*,
        row_number() over (partition by lower(dr.email) order by dr.signup_date, dr.customer_id) as rn
    from distinct_rows dr
),
survivors as (
    -- the original record of each person (10,040 -> 10,000), the 8 source columns
    select
        nu.customer_id, nu.email, nu.signup_date, nu.acquisition_channel,
        nu.segment, nu.country, nu.kyc_status, nu.kyc_date
    from numbered nu
    where nu.rn = 1
),
tidy as (
    -- channel name tidied once, used by the mapping below
    select
        sv.*,
        lower(replace(replace(ltrim(rtrim(sv.acquisition_channel)), ' ', '_'), '-', '_')) as channel_tidy
    from survivors sv
)
select
    t.customer_id,
    t.email,
    t.signup_date,

    -- T-03, T-04: original text kept, standard channel beside it
    t.acquisition_channel as acquisition_channel_raw,
    case t.channel_tidy
         when 'ppc'             then 'paid_search'
         when 'sem'             then 'paid_search'
         when 'fb/ig_ads'       then 'paid_social'
         when 'social_paid'     then 'paid_social'
         when 'aff_network'     then 'affiliate'
         when 'affiliates'      then 'affiliate'
         when 'direct/organic'  then 'organic'
         when 'friend_referral' then 'referral'
         else t.channel_tidy
    end as acquisition_channel,

    -- T-05: a missing (NULL or blank) segment is labelled 'unknown'
    case when t.segment is null or ltrim(rtrim(t.segment)) = '' then 'unknown' else t.segment end as segment,

    t.country,
    t.kyc_status,
    t.kyc_date,

    -- T-06: a decision with no date is flagged
    case when t.kyc_status in ('verified', 'rejected') and t.kyc_date is null then 1 else 0 end as kyc_date_missing
into clean.customers
from tidy t;

-- Checks
-- Rows: 10,100 before, 10,000 after
select (select count(*) from dbo.customers)   as rows_before,
       (select count(*) from clean.customers) as rows_after;

-- One row per customer_id: distinct_ids = total_rows
select count(*) as total_rows, count(distinct customer_id) as distinct_ids
from clean.customers;

-- Exactly the 5 real channels, counts adding up to 10,000
select acquisition_channel, count(*) as customers
from clean.customers
group by acquisition_channel
order by customers desc;

-- Unknown segments and the KYC flag: 378 and 237 (383 and 237 on the raw rows, minus the dropped duplicates)
select sum(case when segment = 'unknown' then 1 else 0 end) as segment_unknown,
       sum(kyc_date_missing) as kyc_date_missing
from clean.customers;
go


/*
================================================================================
PART 4 - VALIDATION
================================================================================
*/

-- Row count log: rows before and after for every table. Only customers loses rows (10,100 to 10,000).
select 'channels'       as tbl, (select count(*) from dbo.channels)       as rows_before, (select count(*) from clean.channels)       as rows_after union all
select 'campaigns',             (select count(*) from dbo.campaigns),                     (select count(*) from clean.campaigns)              union all
select 'accounts',              (select count(*) from dbo.accounts),                      (select count(*) from clean.accounts)               union all
select 'repayments',            (select count(*) from dbo.repayments),                    (select count(*) from clean.repayments)             union all
select 'daily_ad_spend',        (select count(*) from dbo.daily_ad_spend),                (select count(*) from clean.daily_ad_spend)         union all
select 'touchpoints',           (select count(*) from dbo.touchpoints),                   (select count(*) from clean.touchpoints)            union all
select 'loans',                 (select count(*) from dbo.loans),                         (select count(*) from clean.loans)                  union all
select 'assumptions',           (select count(*) from dbo.assumptions),                   (select count(*) from clean.assumptions)            union all
select 'transactions',          (select count(*) from dbo.transactions),                  (select count(*) from clean.transactions)           union all
select 'customers',             (select count(*) from dbo.customers),                     (select count(*) from clean.customers);
