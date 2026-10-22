/*
================================================================================
FINTECH CUSTOMER ACQUISITION AND PROFITABILITY ANALYSIS - DATA PROFILING
================================================================================
Purpose : Systematic table-by-table profiling of the 10 raw tables in schema dbo
          prior to data cleaning. SELECT only: nothing here changes data.

Structure: one section per table, parents first, then the cross-table checks.
          Every check has an ID (CHA-01, CUS-08, XT-04, ...) and a Result line
          with what was found. The IDs are used by the triage table in
          docs/data_profiling.md (findings T-01 to T-18).

How to run: highlight one check and run it, or run the whole script. The queries
          do not depend on each other.
================================================================================
*/

use NeobankGrowth;
go


/*
================================================================================
TABLE 1: dbo.channels (CHA-01 to CHA-04)
================================================================================
Expected : 5 rows, one row per acquisition channel
Columns  : channel_id (1 paid_search, 2 paid_social, 3 affiliate, 4 referral, 5 organic),
          channel_name (canonical names), has_spend (0 for organic: no ad spend rows exist)
================================================================================
*/

-- CHA-01 Row count vs 5
-- Result: 5, matches
select count(*) as total_rows
from dbo.channels ch;


-- CHA-02 channel_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 5 / 5 / 5, clean
select
    count(*) as total_rows,
    count(ch.channel_id) as non_null_ids,
    count(distinct ch.channel_id) as distinct_ids
from dbo.channels ch;


-- CHA-03 channel_name values and stray spaces
-- Result: the 5 canonical names, each once; no variants, no stray spaces
-- Values and how often
select ch.channel_name, count(*) as n
from dbo.channels ch
group by ch.channel_name
order by n desc;

-- Case sensitivity
select ch.channel_name collate Latin1_General_CS_AS as channel_name_cs, count(*) as n
from dbo.channels ch
group by ch.channel_name collate Latin1_General_CS_AS
order by n desc;

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.channels ch
where datalength(ch.channel_name) <> datalength(ltrim(rtrim(ch.channel_name)));

-- Names outside the canonical list
select count(*) as outside_list
from dbo.channels ch
where ch.channel_name not in ('paid_search', 'paid_social', 'affiliate', 'referral', 'organic');


-- CHA-04 has_spend values (0 for organic only)
-- Result: 1 for four channels, 0 for organic
-- Values and how often
select ch.has_spend, count(*) as n
from dbo.channels ch
group by ch.has_spend
order by n desc;

-- The whole table (5 rows): read it
select ch.channel_id, ch.channel_name, ch.has_spend
from dbo.channels ch
order by ch.channel_id;


/*
================================================================================
TABLE 2: dbo.campaigns (CAM-01 to CAM-08)
================================================================================
Expected : 25 rows, one row per marketing campaign
Columns  : campaign_id, channel_id -> channels, campaign_name (prefix = channel family),
          start_date, end_date, objective (acquisition, brand_capture, retargeting, seasonal,
          segment_push, brand_awareness, referral_program, organic)
================================================================================
*/

-- CAM-01 Row count vs 25
-- Result: 25, matches
select count(*) as total_rows
from dbo.campaigns cam;


-- CAM-02 campaign_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 25 / 25 / 25, clean
select
    count(*) as total_rows,
    count(cam.campaign_id) as non_null_ids,
    count(distinct cam.campaign_id) as distinct_ids
from dbo.campaigns cam;


-- CAM-03 NULLs and blanks in every column (blank test for text columns only)
-- Result: none
select
    sum(case when cam.campaign_id is null then 1 else 0 end) as campaign_id_nulls,
    sum(case when cam.channel_id is null then 1 else 0 end) as channel_id_nulls,
    sum(case when cam.campaign_name is null then 1 else 0 end) as campaign_name_nulls,
    sum(case when ltrim(rtrim(cam.campaign_name)) = '' then 1 else 0 end) as campaign_name_blanks,
    sum(case when cam.start_date is null then 1 else 0 end) as start_date_nulls,
    sum(case when cam.end_date is null then 1 else 0 end) as end_date_nulls,
    sum(case when cam.objective is null then 1 else 0 end) as objective_nulls,
    sum(case when ltrim(rtrim(cam.objective)) = '' then 1 else 0 end) as objective_blanks,
    count(*) as total
from dbo.campaigns cam;


-- CAM-04 objective values vs the dictionary list
-- Result: 8 values (acquisition 9, seasonal 4, organic 4, referral_program 3, brand_awareness 2,
--         brand_capture 1, retargeting 1, segment_push 1); all in the list, no variants
-- Values and how often
select cam.objective, count(*) as num
from dbo.campaigns cam
group by cam.objective
order by num desc;

-- Case sensitivity (the default collation can hide 'Organic' vs 'organic')
select cam.objective collate Latin1_General_CS_AS as objective_cs, count(*) as num
from dbo.campaigns cam
group by cam.objective collate Latin1_General_CS_AS
order by num desc;

-- Rows outside the list
select count(*) as outside_list
from dbo.campaigns cam
where cam.objective not in (
    'acquisition', 'brand_capture', 'retargeting', 'seasonal',
    'segment_push', 'brand_awareness', 'referral_program', 'organic'
);

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.campaigns cam
where datalength(cam.objective) <> datalength(ltrim(rtrim(cam.objective)));


-- CAM-05 start_date and end_date span vs the window 2024-10-01 to 2026-09-30
-- Result: start 2024-10-01 to 2026-06-01, end 2025-01-05 to 2026-09-30, all inside
select
    min(cam.start_date) as min_start,
    max(cam.start_date) as max_start,
    min(cam.end_date) as min_end,
    max(cam.end_date) as max_end
from dbo.campaigns cam;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(cam.start_date) < '2024-10-01' then 0 else 1 end as min_start_ok,
    case when max(cam.start_date) > '2026-09-30' then 0 else 1 end as max_start_ok,
    case when min(cam.end_date) < '2024-10-01' then 0 else 1 end as min_end_ok,
    case when max(cam.end_date) > '2026-09-30' then 0 else 1 end as max_end_ok
from dbo.campaigns cam;


-- CAM-06 end_date before start_date
-- Result: 0
select count(*) as ends_before_start
from dbo.campaigns cam
where cam.end_date < cam.start_date;


-- CAM-07 channel_id exists in channels (orphans)
-- Child = campaigns, parent = channels: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.campaigns cam
left join dbo.channels ch
    on cam.channel_id = ch.channel_id
where ch.channel_id is null and cam.channel_id is not null;


-- CAM-08 campaign_name prefix matches the channel (read all 25 rows by eye)
-- Sorted by channel: does each name prefix belong to the channel_name next to it?
-- Result: PS_ paid_search, SO_ paid_social, AF_ affiliate, RF_ referral, OG_ organic; all match
select
    cam.campaign_id,
    cam.campaign_name,
    cam.channel_id,
    ch.channel_name,
    cam.objective
from dbo.campaigns cam
left join dbo.channels ch
    on cam.channel_id = ch.channel_id
order by cam.channel_id, cam.campaign_name;


/*
================================================================================
TABLE 3: dbo.customers (CUS-01 to CUS-14)
================================================================================
Expected : 10,100 rows, one row per SIGNUP RECORD (not per person)
Columns  : customer_id, email (fake, example.com), signup_date,
          acquisition_channel (free text, not standardized),
          segment (student, young_professional, salaried, freelancer),
          country (char(2)), kyc_status (verified, pending, rejected),
          kyc_date (date the KYC decision was made)
================================================================================
*/

-- CUS-01 Row count vs 10,100
-- Result: 10,100, matches
select count(*) as total_rows
from dbo.customers cus;


-- CUS-02 customer_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 10,100 / 10,100 / 10,040: 60 surplus rows from repeated ids (triage T-01)
select
    count(*) as total_rows,
    count(cus.customer_id) as non_null_ids,
    count(distinct cus.customer_id) as distinct_ids
from dbo.customers cus;


-- CUS-03 Repeated customer_id: which ids, how often, are the rows identical?
-- Result: 60 ids, each twice, all exact copies (every column identical)
-- Which ids repeat and how often
select cus.customer_id, count(*) as id_count
from dbo.customers cus
group by cus.customer_id
having count(*) > 1
order by id_count desc;

-- Full rows for a few of those ids (paste ids from the list above)
select *
from dbo.customers cus
where cus.customer_id in (107368, 107889, 103222)
order by cus.customer_id;

-- Repeated ids that are exact copies (every column identical)
with exact_copies as (
    select cus.customer_id
    from dbo.customers cus
    group by
        cus.customer_id, cus.email, cus.signup_date, cus.acquisition_channel,
        cus.segment, cus.country, cus.kyc_status, cus.kyc_date
    having count(*) > 1
)
select count(*) as exact_copy_groups
from exact_copies;


-- CUS-04 Duplicates on email
-- Result: 100 repeated emails = 60 exact copies + 40 re-signups
--         (uppercase email, new id 200001-200040, one day later); triage T-02
-- Emails that appear more than once
select cus.email, count(*) as duplicate_emails
from dbo.customers cus
group by cus.email
having count(*) > 1
order by duplicate_emails desc;

-- Size of the problem: repeated emails and surplus rows
with dup_emails as (
    select cus.email, count(*) as n
    from dbo.customers cus
    group by cus.email
    having count(*) > 1
)
select count(*) as repeated_emails, sum(n - 1) as surplus_rows
from dup_emails;


-- CUS-05 NULLs and blanks in every column (blank test for text columns only)
-- Result: segment 383 NULL, kyc_date 1,393 NULL (triage T-05, T-06); nothing else
select
    sum(case when cus.customer_id is null then 1 else 0 end) as customer_id_nulls,
    sum(case when cus.email is null then 1 else 0 end) as email_nulls,
    sum(case when ltrim(rtrim(cus.email)) = '' then 1 else 0 end) as email_blanks,
    sum(case when cus.signup_date is null then 1 else 0 end) as signup_date_nulls,
    sum(case when cus.acquisition_channel is null then 1 else 0 end) as acquisition_channel_nulls,
    sum(case when ltrim(rtrim(cus.acquisition_channel)) = '' then 1 else 0 end) as acquisition_channel_blanks,
    sum(case when cus.segment is null then 1 else 0 end) as segment_nulls,
    sum(case when ltrim(rtrim(cus.segment)) = '' then 1 else 0 end) as segment_blanks,
    sum(case when cus.country is null then 1 else 0 end) as country_nulls,
    sum(case when ltrim(rtrim(cus.country)) = '' then 1 else 0 end) as country_blanks,
    sum(case when cus.kyc_status is null then 1 else 0 end) as kyc_status_nulls,
    sum(case when ltrim(rtrim(cus.kyc_status)) = '' then 1 else 0 end) as kyc_status_blanks,
    sum(case when cus.kyc_date is null then 1 else 0 end) as kyc_date_nulls,
    count(*) as total
from dbo.customers cus;


-- CUS-06 email: stray spaces, domain is example.com?
-- Result: no stray spaces. LIKE ignores case, so it passes the 40 uppercase re-signups:
--         0 not ending @example.com (a case-sensitive test finds those 40)
-- Stray spaces
select count(*) as emails_with_spaces
from dbo.customers cus
where datalength(cus.email) <> datalength(ltrim(rtrim(cus.email)));

-- Emails that do not end with @example.com
select count(*) as not_example_com
from dbo.customers cus
where cus.email not like '%@example.com';


-- CUS-07 signup_date span vs the window 2024-10-01 to 2026-09-30 (a date, no time)
-- Result: 2024-10-01 to 2026-09-30, inside
select min(cus.signup_date) as first_signup, max(cus.signup_date) as last_signup
from dbo.customers cus;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(cus.signup_date) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(cus.signup_date) > '2026-09-30' then 0 else 1 end as max_ok
from dbo.customers cus;


-- CUS-08 acquisition_channel: distinct values vs the 5 channel names
-- Free text, not standardized: expect spelling, case and spacing variants.
-- Result: 15 values ignoring case, 23 case-sensitive, 256 rows with stray spaces (triage T-03);
--         8 names are not a variant of a channel name (ppc, sem, fb/ig_ads, ...), triage T-04
-- Values and how often (case-insensitive: case variants are merged)
select cus.acquisition_channel, count(*) as n
from dbo.customers cus
group by cus.acquisition_channel
order by n desc;

-- Case sensitivity (case variants shown apart)
select cus.acquisition_channel collate Latin1_General_CS_AS as acquisition_channel_cs, count(*) as n
from dbo.customers cus
group by cus.acquisition_channel collate Latin1_General_CS_AS
order by n desc;

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.customers cus
where datalength(cus.acquisition_channel) <> datalength(ltrim(rtrim(cus.acquisition_channel)));

-- Values that do not exactly match one of the 5 channel names (case-sensitive)
select cus.acquisition_channel, count(*) as n
from dbo.customers cus
left join dbo.channels ch
    on cus.acquisition_channel collate Latin1_General_CS_AS = ch.channel_name collate Latin1_General_CS_AS
where ch.channel_name is null
group by cus.acquisition_channel
order by n desc;

-- Follow-up: how many customer rows do NOT match a channel name exactly?
select count(*) as customer_rows_not_matching
from dbo.customers cus
left join dbo.channels ch
    on cus.acquisition_channel collate Latin1_General_CS_AS = ch.channel_name collate Latin1_General_CS_AS
where ch.channel_name is null;


-- CUS-09 segment values vs the 4 allowed (NULL shows up as its own row, see CUS-05)
-- Result: young_professional 3,052, salaried 2,961, student 2,189, freelancer 1,515, NULL 383; no variants
select cus.segment, count(*) as n
from dbo.customers cus
group by cus.segment
order by n desc;

select cus.segment collate Latin1_General_CS_AS as segment_cs, count(*) as n
from dbo.customers cus
group by cus.segment collate Latin1_General_CS_AS
order by n desc;

-- Rows outside the list (NULL is not counted here)
select count(*) as outside_list
from dbo.customers cus
where cus.segment not in ('student', 'young_professional', 'salaried', 'freelancer');


-- CUS-10 country values, length is 2? (char(2): trailing padding is by design, so test with len())
-- Result: 8 codes (GR 4,048, DE 1,371, FR 1,190, IT 989, ES 928, NL 557, PT 555, IE 462); all length 2
select cus.country, count(*) as n
from dbo.customers cus
group by cus.country
order by n desc;

select cus.country collate Latin1_General_CS_AS as country_cs, count(*) as n
from dbo.customers cus
group by cus.country collate Latin1_General_CS_AS
order by n desc;

-- Rows where the code is not 2 characters long
select count(*) as not_two_chars
from dbo.customers cus
where len(cus.country) <> 2;


-- CUS-11 kyc_status values vs verified / pending / rejected
-- Result: verified 8,329, pending 1,156, rejected 615; no variants, nothing outside the list
select cus.kyc_status, count(*) as n
from dbo.customers cus
group by cus.kyc_status
order by n desc;

select cus.kyc_status collate Latin1_General_CS_AS as kyc_status_cs, count(*) as n
from dbo.customers cus
group by cus.kyc_status collate Latin1_General_CS_AS
order by n desc;

-- Rows outside the list
select count(*) as outside_list
from dbo.customers cus
where cus.kyc_status not in ('verified', 'pending', 'rejected');


-- CUS-12 kyc_date span vs the window 2024-10-01 to 2026-09-30 (a NULL kyc_date drops out of min and max)
-- Result: 2024-10-02 to 2026-09-30, inside
select min(cus.kyc_date) as first_kyc, max(cus.kyc_date) as last_kyc
from dbo.customers cus;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(cus.kyc_date) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(cus.kyc_date) > '2026-09-30' then 0 else 1 end as max_ok
from dbo.customers cus;


-- CUS-13 kyc_date before signup_date (a NULL kyc_date drops out)
-- Result: 0
select count(*) as kyc_before_signup
from dbo.customers cus
where cus.kyc_date < cus.signup_date;


-- CUS-14 kyc_date NULL pattern by kyc_status
-- The dictionary: kyc_date is the date the KYC decision was made.
-- Result: pending 1,156 all NULL (expected); verified 8,103 filled + 226 NULL;
--         rejected 604 filled + 11 NULL. The 237 decisions with no date are triage T-06
select
    cus.kyc_status,
    case when cus.kyc_date is null then 'kyc_date null' else 'kyc_date filled' end as kyc_date_state,
    count(*) as n
from dbo.customers cus
group by
    cus.kyc_status,
    case when cus.kyc_date is null then 'kyc_date null' else 'kyc_date filled' end
order by cus.kyc_status, n desc;


/*
================================================================================
TABLE 4: dbo.daily_ad_spend (ADS-01 to ADS-11)
================================================================================
Expected : 8,747 rows, one row per campaign x active day
Columns  : spend_id, campaign_id -> campaigns, spend_date, spend (EUR), impressions, clicks
Note     : organic campaigns should have no rows; for referral, spend is bonus payouts
================================================================================
*/

-- ADS-01 Row count vs 8,747
-- Result: 8,747, matches
select count(*) as total_rows
from dbo.daily_ad_spend ad;


-- ADS-02 spend_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 8,747 / 8,747 / 8,747, clean
select
    count(*) as total_rows,
    count(ad.spend_id) as non_null_ids,
    count(distinct ad.spend_id) as distinct_ids
from dbo.daily_ad_spend ad;


-- ADS-03 Duplicates on the business key (campaign_id, spend_date)
-- Result: 0 groups
select ad.campaign_id, ad.spend_date, count(*) as num
from dbo.daily_ad_spend ad
group by ad.campaign_id, ad.spend_date
having count(*) > 1;


-- ADS-04 NULLs in every column (no text columns, so no blank test)
-- Result: none
select
    sum(case when ad.spend_id is null then 1 else 0 end) as spend_id_nulls,
    sum(case when ad.campaign_id is null then 1 else 0 end) as campaign_id_nulls,
    sum(case when ad.spend_date is null then 1 else 0 end) as spend_date_nulls,
    sum(case when ad.spend is null then 1 else 0 end) as spend_nulls,
    sum(case when ad.impressions is null then 1 else 0 end) as impressions_nulls,
    sum(case when ad.clicks is null then 1 else 0 end) as clicks_nulls,
    count(*) as total
from dbo.daily_ad_spend ad;


-- ADS-05 spend range, zeros, negatives
-- Result: 0.43 to 316.49, average 17.38, no zeros, no negatives (the high end is looked at in Question 5)
select
    min(ad.spend) as min_spend,
    max(ad.spend) as max_spend,
    avg(ad.spend) as avg_spend,
    sum(case when ad.spend < 0 then 1 else 0 end) as negatives,
    sum(case when ad.spend = 0 then 1 else 0 end) as zeros
from dbo.daily_ad_spend ad;


-- ADS-06 impressions and clicks range, zeros, negatives
-- Result: no negatives; 122 rows with zero impressions, 127 with zero clicks (triage T-14).
--         The money was spent, so zero-impression rows stay in spend
select
    min(ad.impressions) as min_impressions,
    max(ad.impressions) as max_impressions,
    avg(ad.impressions) as avg_impressions,
    sum(case when ad.impressions < 0 then 1 else 0 end) as impression_negatives,
    sum(case when ad.impressions = 0 then 1 else 0 end) as impression_zeros,
    min(ad.clicks) as min_clicks,
    max(ad.clicks) as max_clicks,
    avg(ad.clicks) as avg_clicks,
    sum(case when ad.clicks < 0 then 1 else 0 end) as click_negatives,
    sum(case when ad.clicks = 0 then 1 else 0 end) as click_zeros
from dbo.daily_ad_spend ad;


-- ADS-07 spend_date span vs the window 2024-10-01 to 2026-09-30
-- Result: 2024-10-01 to 2026-09-30, inside
select min(ad.spend_date) as first_date, max(ad.spend_date) as last_date
from dbo.daily_ad_spend ad;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(ad.spend_date) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(ad.spend_date) > '2026-09-30' then 0 else 1 end as max_ok
from dbo.daily_ad_spend ad;


-- ADS-08 campaign_id exists in campaigns (orphans)
-- Child = daily_ad_spend, parent = campaigns: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.daily_ad_spend ad
left join dbo.campaigns cam
    on ad.campaign_id = cam.campaign_id
where cam.campaign_id is null and ad.campaign_id is not null;


-- ADS-09 clicks greater than impressions
-- Result: 0
select count(*) as clicks_over_impressions
from dbo.daily_ad_spend ad
where ad.clicks > ad.impressions;


-- ADS-10 spend_date outside the campaign's start/end dates
-- Relies on campaign_id being unique in campaigns (CAM-02), otherwise the join repeats spend rows
-- Result: 0
select count(*) as spend_outside_flight
from dbo.daily_ad_spend ad
inner join dbo.campaigns cam
    on ad.campaign_id = cam.campaign_id
where ad.spend_date < cam.start_date
   or ad.spend_date > cam.end_date;


-- ADS-11 spend rows for organic campaigns (the dictionary says none)
-- Two angles: the campaign objective, and channel_id 5 (organic)
-- Result: 0 and 0
select
    sum(case when cam.objective = 'organic' then 1 else 0 end) as objective_organic_rows,
    sum(case when cam.channel_id = 5 then 1 else 0 end) as channel_5_rows
from dbo.daily_ad_spend ad
inner join dbo.campaigns cam
    on ad.campaign_id = cam.campaign_id;


/*
================================================================================
TABLE 5: dbo.touchpoints (TOU-01 to TOU-09)
================================================================================
Expected : 21,019 rows, one row per marketing interaction before signup
Columns  : touchpoint_id, customer_id -> customers, campaign_id -> campaigns,
          touch_ts (datetime), touch_type (impression, click)
================================================================================
*/

-- TOU-01 Row count vs 21,019
-- Result: 21,019, matches
select count(*) as total_rows
from dbo.touchpoints tch;


-- TOU-02 touchpoint_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 21,019 / 21,019 / 21,019, clean
select
    count(*) as total_rows,
    count(tch.touchpoint_id) as non_null_ids,
    count(distinct tch.touchpoint_id) as distinct_ids
from dbo.touchpoints tch;


-- TOU-03 Duplicates on the business key (customer_id, campaign_id, touch_ts, touch_type)
-- Result: 0 groups
select tch.customer_id, tch.campaign_id, tch.touch_ts, tch.touch_type, count(*) as num
from dbo.touchpoints tch
group by tch.customer_id, tch.campaign_id, tch.touch_ts, tch.touch_type
having count(*) > 1;


-- TOU-04 NULLs in every column (blank test for text columns only)
-- Result: none
select
    sum(case when tch.touchpoint_id is null then 1 else 0 end) as touchpoint_id_nulls,
    sum(case when tch.customer_id is null then 1 else 0 end) as customer_id_nulls,
    sum(case when tch.campaign_id is null then 1 else 0 end) as campaign_id_nulls,
    sum(case when tch.touch_ts is null then 1 else 0 end) as touch_ts_nulls,
    sum(case when tch.touch_type is null then 1 else 0 end) as touch_type_nulls,
    sum(case when rtrim(ltrim(tch.touch_type)) = '' then 1 else 0 end) as touch_type_blanks,
    count(*) as total
from dbo.touchpoints tch;


-- TOU-05 touch_type values vs the dictionary list (impression, click)
-- Result: click 18,348, impression 2,671; no case variants, no stray spaces, nothing outside the list
-- Values and how often
select tch.touch_type, count(*) as num
from dbo.touchpoints tch
group by tch.touch_type
order by num desc;

-- Case sensitivity (the default collation can hide 'Click' vs 'click')
select tch.touch_type collate Latin1_General_CS_AS as touch_type_cs, count(*) as num
from dbo.touchpoints tch
group by tch.touch_type collate Latin1_General_CS_AS
order by num desc;

-- Rows outside the list
select count(*) as outside_list
from dbo.touchpoints tch
where tch.touch_type not in ('impression', 'click');

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.touchpoints tch
where datalength(tch.touch_type) <> datalength(ltrim(rtrim(tch.touch_type)));


-- TOU-06 touch_ts span vs the window 2024-10-01 to 2026-09-30
-- touch_ts has a TIME part: the upper bound is ">= next day"
-- (max(touch_ts) > '2026-09-30' would wrongly flag touches on the last day)
-- Result: 2024-10-01 to 2026-09-30, inside
select min(tch.touch_ts) as first_touch, max(tch.touch_ts) as last_touch
from dbo.touchpoints tch;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(tch.touch_ts) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(tch.touch_ts) >= '2026-10-01' then 0 else 1 end as max_ok
from dbo.touchpoints tch;


-- TOU-07 customer_id exists in customers (orphans)
-- Child = touchpoints, parent = customers: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.touchpoints tch
left join dbo.customers cus
    on tch.customer_id = cus.customer_id
where cus.customer_id is null and tch.customer_id is not null;


-- TOU-08 campaign_id exists in campaigns (orphans)
-- Child = touchpoints, parent = campaigns
-- Result: 0 orphans
select count(*) as orphans
from dbo.touchpoints tch
left join dbo.campaigns cam
    on tch.campaign_id = cam.campaign_id
where cam.campaign_id is null and tch.campaign_id is not null;


-- TOU-09 touch_ts after the customer's signup_date
-- Dictionary: a touchpoint happens BEFORE signup, so a touch on a later day breaks the rule.
-- signup_date has no time, so same-day touches cannot be judged: counted apart.
-- count(distinct): customers repeats 60 ids.
-- Result: 0 touches after the signup day; 2,586 on the signup day (triage T-08)
-- Touches on a later day than the signup date
select count(distinct tch.touchpoint_id) as touch_after_signup_day
from dbo.touchpoints tch
inner join dbo.customers cus
    on tch.customer_id = cus.customer_id
where cast(tch.touch_ts as date) > cus.signup_date;

-- Touches on the signup day (information only)
select count(distinct tch.touchpoint_id) as touch_on_signup_day
from dbo.touchpoints tch
inner join dbo.customers cus
    on tch.customer_id = cus.customer_id
where cast(tch.touch_ts as date) = cus.signup_date;


/*
================================================================================
TABLE 6: dbo.accounts (ACC-01 to ACC-11)
================================================================================
Expected : 9,806 rows, one row per account
Columns  : account_id, customer_id -> customers, account_type, open_date, status, close_date
================================================================================
*/

-- ACC-01 Row count vs 9,806
-- Result: 9,806, matches
select count(*) as total_rows
from dbo.accounts acc;


-- ACC-02 account_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 9,806 / 9,806 / 9,806, clean
select
    count(*) as total_rows,
    count(acc.account_id) as non_null_ids,
    count(distinct acc.account_id) as distinct_ids
from dbo.accounts acc;


-- ACC-03 Customers with more than one account
-- Result: 1,525 customers have 2 accounts = the 1,525 savings accounts (current + savings), triage T-09
select acc.customer_id, count(*) as num
from dbo.accounts acc
group by acc.customer_id
having count(*) > 1;


-- ACC-04 NULLs in every column (blank test for text columns only)
-- Result: only close_date has NULLs (8,265), expected for accounts not closed (see ACC-08)
select
    sum(case when acc.account_id is null then 1 else 0 end) as account_id_nulls,
    sum(case when acc.customer_id is null then 1 else 0 end) as customer_id_nulls,
    sum(case when acc.account_type is null then 1 else 0 end) as account_type_nulls,
    sum(case when rtrim(ltrim(acc.account_type)) = '' then 1 else 0 end) as account_type_blanks,
    sum(case when acc.open_date is null then 1 else 0 end) as open_date_nulls,
    sum(case when acc.status is null then 1 else 0 end) as status_nulls,
    sum(case when rtrim(ltrim(acc.status)) = '' then 1 else 0 end) as status_blanks,
    sum(case when acc.close_date is null then 1 else 0 end) as close_date_nulls,
    count(*) as total
from dbo.accounts acc;


-- ACC-05 account_type (current, savings, business) and status (open, dormant, closed)
-- Result: current 7,847, savings 1,525, business 434 | dormant 4,719, open 3,546, closed 1,541. No value outside the lists
-- account_type values
select acc.account_type, count(*) as num
from dbo.accounts acc
group by acc.account_type
order by num desc;

-- status values
select acc.status, count(*) as num
from dbo.accounts acc
group by acc.status
order by num desc;

-- Rows outside the lists
select count(*) as outside_list
from dbo.accounts acc
where acc.account_type not in ('current', 'savings', 'business')
   or acc.status not in ('open', 'dormant', 'closed');

-- Case sensitivity (the default collation can hide 'Open' vs 'open')
select
    acc.status collate Latin1_General_CS_AS as status_cs,
    acc.account_type collate Latin1_General_CS_AS as account_type_cs,
    count(*) as num
from dbo.accounts acc
group by
    acc.status collate Latin1_General_CS_AS,
    acc.account_type collate Latin1_General_CS_AS
order by num desc;


-- ACC-06 open_date and close_date span vs the window 2024-10-01 to 2026-09-30
-- Result: open 2024-10-02 to 2026-09-30, close 2024-10-30 to 2026-09-30, all inside
select
    min(acc.open_date) as min_open,
    max(acc.open_date) as max_open,
    min(acc.close_date) as min_close,
    max(acc.close_date) as max_close
from dbo.accounts acc;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(acc.open_date) < '2024-10-01' then 0 else 1 end as min_open_ok,
    case when max(acc.open_date) > '2026-09-30' then 0 else 1 end as max_open_ok,
    case when min(acc.close_date) < '2024-10-01' then 0 else 1 end as min_close_ok,
    case when max(acc.close_date) > '2026-09-30' then 0 else 1 end as max_close_ok
from dbo.accounts acc;


-- ACC-07 customer_id exists in customers (orphans)
-- Child = accounts, parent = customers: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.accounts acc
left join dbo.customers cus
    on acc.customer_id = cus.customer_id
where cus.customer_id is null and acc.customer_id is not null;


-- ACC-08 close_date NULL exactly when status is closed
-- Result: closed = filled (1,541); open and dormant = NULL (3,546 + 4,719). The rule holds
select
    acc.status,
    case when acc.close_date is null then 'close_date null' else 'close_date filled' end as close_date_state,
    count(*) as n
from dbo.accounts acc
group by
    acc.status,
    case when acc.close_date is null then 'close_date null' else 'close_date filled' end
order by acc.status, n desc;


-- ACC-09 close_date before open_date (a NULL close_date drops out)
-- Result: 0
select count(*) as closed_before_open
from dbo.accounts acc
where acc.close_date < acc.open_date;


-- ACC-10 open_date before the customer's signup_date
-- count(distinct): customers repeats 60 ids, so an account could join to two rows
-- Result: 0
select count(distinct acc.account_id) as opened_before_signup
from dbo.accounts acc
inner join dbo.customers cus
    on acc.customer_id = cus.customer_id
where acc.open_date < cus.signup_date;


-- ACC-11 accounts of customers who are not KYC verified
-- Dictionary rule: accounts open only after KYC verification
-- Result: all 9,806 accounts belong to verified customers; 0 opened before the KYC date
-- KYC status of the account holders
select cus.kyc_status, count(distinct acc.account_id) as accounts
from dbo.accounts acc
inner join dbo.customers cus
    on acc.customer_id = cus.customer_id
group by cus.kyc_status
order by accounts desc;

-- Accounts opened before the KYC decision date (a NULL kyc_date drops out)
select count(distinct acc.account_id) as opened_before_kyc
from dbo.accounts acc
inner join dbo.customers cus
    on acc.customer_id = cus.customer_id
where acc.open_date < cus.kyc_date;


/*
================================================================================
TABLE 7: dbo.transactions (TXN-01 to TXN-11)
================================================================================
Expected : 64,908 rows, one row per account transaction
Columns  : txn_id, account_id -> accounts, txn_ts (datetime),
          txn_type (deposit, card_spend, transfer, withdrawal),
          amount (EUR; direction is carried by txn_type, so amounts should be positive),
          merchant_category (card_spend only)
================================================================================
*/

-- TXN-01 Row count vs 64,908
-- Result: 64,908, matches
select count(*) as total_rows
from dbo.transactions trs;


-- TXN-02 txn_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 64,908 / 64,908 / 64,908, clean
select
    count(*) as total_rows,
    count(trs.txn_id) as non_null_ids,
    count(distinct trs.txn_id) as distinct_ids
from dbo.transactions trs;


-- TXN-03 Duplicates on the business key (account_id, txn_ts, txn_type, amount)
-- Result: 0 groups
select trs.account_id, trs.txn_ts, trs.txn_type, trs.amount, count(*) as num
from dbo.transactions trs
group by trs.account_id, trs.txn_ts, trs.txn_type, trs.amount
having count(*) > 1;


-- TXN-04 NULLs and blanks in every column (blank test for text columns only)
-- Result: only merchant_category has NULLs (30,325): expected for non-card_spend, see TXN-10
select
    sum(case when trs.txn_id is null then 1 else 0 end) as txn_id_nulls,
    sum(case when trs.account_id is null then 1 else 0 end) as account_id_nulls,
    sum(case when trs.txn_ts is null then 1 else 0 end) as txn_ts_nulls,
    sum(case when trs.txn_type is null then 1 else 0 end) as txn_type_nulls,
    sum(case when ltrim(rtrim(trs.txn_type)) = '' then 1 else 0 end) as txn_type_blanks,
    sum(case when trs.amount is null then 1 else 0 end) as amount_nulls,
    sum(case when trs.merchant_category is null then 1 else 0 end) as merchant_category_nulls,
    sum(case when ltrim(rtrim(trs.merchant_category)) = '' then 1 else 0 end) as merchant_category_blanks,
    count(*) as total
from dbo.transactions trs;


-- TXN-05 txn_type values vs the dictionary list
-- Result: card_spend 35,652, deposit 16,883, transfer 8,765, withdrawal 3,608; no variants, nothing outside the list
-- Values and how often
select trs.txn_type, count(*) as num
from dbo.transactions trs
group by trs.txn_type
order by num desc;

-- Case sensitivity (the default collation can hide 'Deposit' vs 'deposit')
select trs.txn_type collate Latin1_General_CS_AS as txn_type_cs, count(*) as num
from dbo.transactions trs
group by trs.txn_type collate Latin1_General_CS_AS
order by num desc;

-- Rows outside the list
select count(*) as outside_list
from dbo.transactions trs
where trs.txn_type not in ('deposit', 'card_spend', 'transfer', 'withdrawal');

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.transactions trs
where datalength(trs.txn_type) <> datalength(ltrim(rtrim(trs.txn_type)));


-- TXN-06 amount range, zeros, negatives (the dictionary says positive)
-- Result: min -4,156.95, max 379,178, average 260.68, no zeros.
--         323 negatives, in every type (triage T-10); the very large maximum is triage T-18
select
    min(trs.amount) as min_amount,
    max(trs.amount) as max_amount,
    avg(trs.amount) as avg_amount,
    sum(case when trs.amount < 0 then 1 else 0 end) as negatives,
    sum(case when trs.amount = 0 then 1 else 0 end) as zeros
from dbo.transactions trs;

-- Types of the negative amounts (read at triage): card_spend 129, deposit 91, transfer 80, withdrawal 23
select trs.txn_type, count(*) as negative_rows
from dbo.transactions trs
where trs.amount < 0
group by trs.txn_type
order by negative_rows desc;

-- Follow-up (triage T-10): average size ignoring the sign, negative vs positive rows of the same type.
-- Close values mean sign flips, not corrupted values. Result: deposit 859 vs 737, transfer 146 vs 158,
-- card_spend 61 vs 82, withdrawal 72 vs 102
select
    trs.txn_type,
    case when trs.amount < 0 then 'negative' else 'positive' end as amount_sign,
    count(*) as n,
    abs(avg(trs.amount)) as avg_size
from dbo.transactions trs
group by
    trs.txn_type,
    case when trs.amount < 0 then 'negative' else 'positive' end
order by trs.txn_type, amount_sign;


-- TXN-07 txn_ts span vs the window 2024-10-01 to 2026-09-30
-- txn_ts has a TIME part: the upper bound is ">= next day"
-- Result: 5 transactions before the window (earliest 2024-09-21 15:58:59), none after (triage T-13)
select min(trs.txn_ts) as first_txn, max(trs.txn_ts) as last_txn
from dbo.transactions trs;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(trs.txn_ts) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(trs.txn_ts) >= '2026-10-01' then 0 else 1 end as max_ok
from dbo.transactions trs;

-- Transactions after 2026-09-30
select count(*) as after_asof
from dbo.transactions trs
where trs.txn_ts >= '2026-10-01';

-- Follow-up: how many are before the window, and from when?
select count(*) as before_window, min(trs.txn_ts) as earliest
from dbo.transactions trs
where trs.txn_ts < '2024-10-01';

-- Follow-up: look at them
select top 20 trs.*
from dbo.transactions trs
where trs.txn_ts < '2024-10-01'
order by trs.txn_ts;


-- TXN-08 merchant_category values (NULL shows up as its own row)
-- Result: 9 categories (groceries 9,468 the largest, other 1,370 the smallest), no variants
-- Values and how often
select trs.merchant_category, count(*) as num
from dbo.transactions trs
group by trs.merchant_category
order by num desc;

-- Case sensitivity
select trs.merchant_category collate Latin1_General_CS_AS as merchant_category_cs, count(*) as num
from dbo.transactions trs
group by trs.merchant_category collate Latin1_General_CS_AS
order by num desc;

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.transactions trs
where datalength(trs.merchant_category) <> datalength(ltrim(rtrim(trs.merchant_category)));


-- TXN-09 account_id exists in accounts (orphans)
-- Child = transactions, parent = accounts: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.transactions trs
left join dbo.accounts acc
    on trs.account_id = acc.account_id
where acc.account_id is null and trs.account_id is not null;


-- TXN-10 merchant_category filled only for card_spend
-- Expected: card_spend + filled; every other type + null
-- Result: other types always null; card_spend filled 34,583 and null 1,069 (triage T-11)
select
    trs.txn_type,
    case
        when trs.merchant_category is null then 'null'
        when ltrim(rtrim(trs.merchant_category)) = '' then 'blank'
        else 'filled'
    end as merchant_category_state,
    count(*) as n
from dbo.transactions trs
group by
    trs.txn_type,
    case
        when trs.merchant_category is null then 'null'
        when ltrim(rtrim(trs.merchant_category)) = '' then 'blank'
        else 'filled'
    end
order by trs.txn_type, n desc;


-- TXN-11 txn_ts before the account's open_date or after its close_date
-- txn_ts has a time, open_date and close_date are dates: compare on the date.
-- A NULL close_date (not closed) drops out of "after close".
-- Relies on account_id being unique in accounts (ACC-02).
-- Result: 389 before open (triage T-12), 0 after close
select
    sum(case when cast(trs.txn_ts as date) < acc.open_date then 1 else 0 end) as before_open,
    sum(case when cast(trs.txn_ts as date) > acc.close_date then 1 else 0 end) as after_close,
    count(*) as transactions_checked
from dbo.transactions trs
inner join dbo.accounts acc
    on trs.account_id = acc.account_id;

-- Follow-up (triage T-12): how early is each of the 389 transactions?
-- Result: about 10 rows 1 to 2 days early, about 367 rows 3 to 30 days early, 12 rows over 30 days (up to 135)
select
    trs.txn_id,
    trs.txn_ts,
    acc.open_date,
    datediff(day, cast(trs.txn_ts as date), acc.open_date) as days_early
from dbo.transactions trs
inner join dbo.accounts acc
    on trs.account_id = acc.account_id
where cast(trs.txn_ts as date) < acc.open_date
order by days_early desc;


/*
================================================================================
TABLE 8: dbo.loans (LOA-01 to LOA-09)
================================================================================
Expected : 2,290 rows, one row per loan
Columns  : loan_id, customer_id -> customers, issue_date, principal (EUR),
          apr (percent per year), term_months (6, 12, 18 or 24), grade (A best to G worst)
================================================================================
*/

-- LOA-01 Row count vs 2,290
-- Result: 2,290, matches
select count(*) as total_rows
from dbo.loans lon;


-- LOA-02 loan_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 2,290 / 2,290 / 2,290, clean
select
    count(*) as total_rows,
    count(lon.loan_id) as non_null_ids,
    count(distinct lon.loan_id) as distinct_ids
from dbo.loans lon;


-- LOA-03 NULLs and blanks in every column (blank test for text columns only)
-- Result: none
select
    sum(case when lon.loan_id is null then 1 else 0 end) as loan_id_nulls,
    sum(case when lon.customer_id is null then 1 else 0 end) as customer_id_nulls,
    sum(case when lon.issue_date is null then 1 else 0 end) as issue_date_nulls,
    sum(case when lon.principal is null then 1 else 0 end) as principal_nulls,
    sum(case when lon.apr is null then 1 else 0 end) as apr_nulls,
    sum(case when lon.term_months is null then 1 else 0 end) as term_months_nulls,
    sum(case when lon.grade is null then 1 else 0 end) as grade_nulls,
    sum(case when ltrim(rtrim(lon.grade)) = '' then 1 else 0 end) as grade_blanks,
    count(*) as total
from dbo.loans lon;


-- LOA-04 principal and apr range, zeros, negatives
-- Result: principal 600 to 20,000 (average 4,920.70), apr 8.00 to 35.96 (average 17.21); no zeros, no negatives
select
    min(lon.principal) as min_principal,
    max(lon.principal) as max_principal,
    avg(lon.principal) as avg_principal,
    sum(case when lon.principal < 0 then 1 else 0 end) as principal_negatives,
    sum(case when lon.principal = 0 then 1 else 0 end) as principal_zeros,
    min(lon.apr) as min_apr,
    max(lon.apr) as max_apr,
    avg(lon.apr) as avg_apr,
    sum(case when lon.apr < 0 then 1 else 0 end) as apr_negatives,
    sum(case when lon.apr = 0 then 1 else 0 end) as apr_zeros
from dbo.loans lon;


-- LOA-05 term_months values vs 6, 12, 18, 24
-- Result: 6 = 340, 12 = 905, 18 = 464, 24 = 581; nothing outside the list
select lon.term_months, count(*) as num
from dbo.loans lon
group by lon.term_months
order by lon.term_months;

-- Rows outside the list
select count(*) as outside_list
from dbo.loans lon
where lon.term_months not in (6, 12, 18, 24);


-- LOA-06 grade values vs A to G
-- Result: A 399, B 668, C 649, D 355, E 149, F 53, G 17; no variants, nothing outside A to G
-- Values and how often
select lon.grade, count(*) as num
from dbo.loans lon
group by lon.grade
order by lon.grade;

-- Case sensitivity (the default collation can hide 'a' vs 'A')
select lon.grade collate Latin1_General_CS_AS as grade_cs, count(*) as num
from dbo.loans lon
group by lon.grade collate Latin1_General_CS_AS
order by grade_cs;

-- Rows outside A to G
select count(*) as outside_list
from dbo.loans lon
where lon.grade not in ('A', 'B', 'C', 'D', 'E', 'F', 'G');

-- Stray spaces
select count(*) as rows_with_spaces
from dbo.loans lon
where datalength(lon.grade) <> datalength(ltrim(rtrim(lon.grade)));


-- LOA-07 issue_date span vs the window 2024-10-01 to 2026-09-30
-- Result: 2024-11-08 to 2026-09-10, inside
select min(lon.issue_date) as first_issue, max(lon.issue_date) as last_issue
from dbo.loans lon;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(lon.issue_date) < '2024-10-01' then 0 else 1 end as min_ok,
    case when max(lon.issue_date) > '2026-09-30' then 0 else 1 end as max_ok
from dbo.loans lon;


-- LOA-08 customer_id exists in customers (orphans)
-- Child = loans, parent = customers: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.loans lon
left join dbo.customers cus
    on lon.customer_id = cus.customer_id
where cus.customer_id is null and lon.customer_id is not null;


-- LOA-09 loan customers who have no account
-- A customer can have several accounts, so count distinct loans
-- Result: 0
select count(distinct lon.loan_id) as loans_without_account
from dbo.loans lon
left join dbo.accounts acc
    on lon.customer_id = acc.customer_id
where acc.customer_id is null and lon.customer_id is not null;


/*
================================================================================
TABLE 9: dbo.repayments (REP-01 to REP-11)
================================================================================
Expected : 19,190 rows, one row per scheduled installment due on or before 2026-09-30
Columns  : repayment_id, loan_id -> loans, installment_no (1..term_months), due_date,
          paid_date (NULL if not paid), amount_due (fixed installment), amount_paid (0 if unpaid)
Note     : DPD (days past due) is not stored; it is derived later from due_date and paid_date
================================================================================
*/

-- REP-01 Row count vs 19,190
-- Result: 19,190, matches
select count(*) as total_rows
from dbo.repayments rep;


-- REP-02 repayment_id unique, no NULL
-- total vs non_null = NULL ids; non_null vs distinct = duplicate ids
-- Result: 19,190 / 19,190 / 19,190, clean
select
    count(*) as total_rows,
    count(rep.repayment_id) as non_null_ids,
    count(distinct rep.repayment_id) as distinct_ids
from dbo.repayments rep;


-- REP-03 Duplicates on the business key (loan_id, installment_no)
-- Result: 0 groups
select rep.loan_id, rep.installment_no, count(*) as num
from dbo.repayments rep
group by rep.loan_id, rep.installment_no
having count(*) > 1;


-- REP-04 NULLs in every column
-- Result: only paid_date has NULLs (2,030), expected for unpaid installments (see REP-09)
select
    sum(case when rep.repayment_id is null then 1 else 0 end) as repayment_id_nulls,
    sum(case when rep.loan_id is null then 1 else 0 end) as loan_id_nulls,
    sum(case when rep.installment_no is null then 1 else 0 end) as installment_no_nulls,
    sum(case when rep.due_date is null then 1 else 0 end) as due_date_nulls,
    sum(case when rep.paid_date is null then 1 else 0 end) as paid_date_nulls,
    sum(case when rep.amount_due is null then 1 else 0 end) as amount_due_nulls,
    sum(case when rep.amount_paid is null then 1 else 0 end) as amount_paid_nulls,
    count(*) as total
from dbo.repayments rep;


-- REP-05 amount_due and amount_paid range, zeros, negatives
-- Result: due 29.78 to 3,442.08 (average 390.54); paid 0 to 3,442.08 (average 344.85);
--         no negatives; amount_paid = 0 on 2,030 rows, expected for unpaid (see REP-09)
select
    min(rep.amount_due) as min_due,
    max(rep.amount_due) as max_due,
    avg(rep.amount_due) as avg_due,
    sum(case when rep.amount_due < 0 then 1 else 0 end) as due_negatives,
    sum(case when rep.amount_due = 0 then 1 else 0 end) as due_zeros,
    min(rep.amount_paid) as min_paid,
    max(rep.amount_paid) as max_paid,
    avg(rep.amount_paid) as avg_paid,
    sum(case when rep.amount_paid < 0 then 1 else 0 end) as paid_negatives,
    sum(case when rep.amount_paid = 0 then 1 else 0 end) as paid_zeros
from dbo.repayments rep;


-- REP-06 due_date and paid_date span vs the window 2024-10-01 to 2026-09-30
-- Result: due 2024-12-08 to 2026-09-30, paid 2024-12-10 to 2026-09-30; none after the as-of date
select
    min(rep.due_date) as min_due,
    max(rep.due_date) as max_due,
    min(rep.paid_date) as min_paid,
    max(rep.paid_date) as max_paid
from dbo.repayments rep;

-- Same test as 1 (inside the window) / 0 (outside)
select
    case when min(rep.due_date) < '2024-10-01' then 0 else 1 end as min_due_ok,
    case when max(rep.due_date) > '2026-09-30' then 0 else 1 end as max_due_ok,
    case when min(rep.paid_date) < '2024-10-01' then 0 else 1 end as min_paid_ok,
    case when max(rep.paid_date) > '2026-09-30' then 0 else 1 end as max_paid_ok
from dbo.repayments rep;


-- REP-07 loan_id exists in loans (orphans)
-- Child = repayments, parent = loans: start from the child
-- Result: 0 orphans
select count(*) as orphans
from dbo.repayments rep
left join dbo.loans lon
    on rep.loan_id = lon.loan_id
where lon.loan_id is null and rep.loan_id is not null;


-- REP-08 installment_no within 1 to term_months
-- Compares a number on the child with a limit on the parent (loans)
-- Result: 0 outside the term
select count(*) as outside_term
from dbo.repayments rep
inner join dbo.loans lon
    on rep.loan_id = lon.loan_id
where rep.installment_no < 1
   or rep.installment_no > lon.term_months;


-- REP-09 paid_date NULL exactly when amount_paid is 0
-- Expected: paid_date null + amount zero; paid_date filled + amount not zero
-- Result: 17,160 filled + not zero, 2,030 null + zero; no other combination. The rule holds
select
    case when rep.paid_date is null then 'paid_date null' else 'paid_date filled' end as paid_date_state,
    case when rep.amount_paid = 0 then 'amount_paid zero' else 'amount_paid not zero' end as amount_paid_state,
    count(*) as n
from dbo.repayments rep
group by
    case when rep.paid_date is null then 'paid_date null' else 'paid_date filled' end,
    case when rep.amount_paid = 0 then 'amount_paid zero' else 'amount_paid not zero' end
order by n desc;


-- REP-10 amount_paid greater than amount_due
-- Result: 0
select count(*) as overpaid
from dbo.repayments rep
where rep.amount_paid > rep.amount_due;


-- REP-11 installments per loan vs the loan term
-- Only installments due on or before 2026-09-30 exist, so recent loans can have fewer than their term.
-- Loans with no repayments show installments = NULL.
-- Result: no loan has more installments than its term; fewer ones are recent loans;
--         29 loans issued 2026-09-01 to 2026-09-10 have none yet (triage T-16)
with cnt as (
    -- one row per loan: how many installments it has
    select r.loan_id, count(*) as installments
    from dbo.repayments r
    group by r.loan_id
)
select lon.term_months, cnt.installments, count(*) as loans
from dbo.loans lon
left join cnt
    on lon.loan_id = cnt.loan_id
group by lon.term_months, cnt.installments
order by lon.term_months, cnt.installments;

-- Follow-up 1: loans with MORE installments than their term (should be 0)
with cnt as (
    select r.loan_id, count(*) as installments
    from dbo.repayments r
    group by r.loan_id
)
select count(*) as more_than_term
from dbo.loans lon
inner join cnt
    on lon.loan_id = cnt.loan_id
where cnt.installments > lon.term_months;

-- Follow-up 2: loans with FEWER installments than their term: how recent are they?
with cnt as (
    select r.loan_id, count(*) as installments
    from dbo.repayments r
    group by r.loan_id
)
select lon.term_months, cnt.installments,
       min(lon.issue_date) as earliest_issue, max(lon.issue_date) as latest_issue,
       count(*) as loans
from dbo.loans lon
inner join cnt
    on lon.loan_id = cnt.loan_id
where cnt.installments < lon.term_months
group by lon.term_months, cnt.installments
order by lon.term_months, cnt.installments;

-- Follow-up 3: loans with no repayments at all: how recent are they?
select lon.term_months, count(*) as loans_without_repayments,
       min(lon.issue_date) as earliest_issue, max(lon.issue_date) as latest_issue
from dbo.loans lon
left join dbo.repayments rep
    on lon.loan_id = rep.loan_id
where rep.loan_id is null
group by lon.term_months
order by lon.term_months;


/*
================================================================================
TABLE 10: dbo.assumptions (ASM-01 to ASM-01)
================================================================================
Expected : 8 rows, one row per revenue or cost assumption
Use      : LTV and payback later (interchange rate, deposit margin, cost of funds,
          loss given default, origination fee, KYC cost, servicing cost)
================================================================================
*/

-- ASM-01 Read all 8 rows: what each means and its unit
-- Result: 8 rows. Rates: interchange 0.003, deposit margin 0.015, cost of funds 0.045, origination fee 0.03,
--         loss given default 0.9. EUR: KYC 2.5, servicing 0.4. Date: as-of 20260930.
--         assumption_value is a float (noise on 6 values) and mixes rates, EUR and a date (triage T-15)
-- Row count (dictionary: 8)
select count(*) as total_rows
from dbo.assumptions asm;

-- Column names and types
select COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
from INFORMATION_SCHEMA.COLUMNS
where TABLE_SCHEMA = 'dbo' and TABLE_NAME = 'assumptions'
order by ORDINAL_POSITION;

-- The 8 rows
select *
from dbo.assumptions asm;


/*
================================================================================
TABLE 11: CROSS-TABLE CHECKS (XT-01 to XT-04)
================================================================================
          Run after every single table has been profiled; these checks look ACROSS tables
================================================================================
*/

-- XT-01 Row counts of all 10 tables vs the dictionary (total 136,098)
-- diff = actual - expected
-- Result: diff 0 for every table; total 136,098, the load is complete
with counts as (
    select 'channels' as table_name, 5 as expected, count(*) as actual from dbo.channels
    union all select 'campaigns', 25, count(*) from dbo.campaigns
    union all select 'daily_ad_spend', 8747, count(*) from dbo.daily_ad_spend
    union all select 'customers', 10100, count(*) from dbo.customers
    union all select 'touchpoints', 21019, count(*) from dbo.touchpoints
    union all select 'accounts', 9806, count(*) from dbo.accounts
    union all select 'transactions', 64908, count(*) from dbo.transactions
    union all select 'loans', 2290, count(*) from dbo.loans
    union all select 'repayments', 19190, count(*) from dbo.repayments
    union all select 'assumptions', 8, count(*) from dbo.assumptions
)
select table_name, expected, actual, actual - expected as diff
from counts
union all
select 'TOTAL', sum(expected), sum(actual), sum(actual) - sum(expected)
from counts;


-- XT-02 Every foreign key has a parent (summary of all orphan checks)
-- One row per link, child -> parent; orphans = child rows whose key is missing in the parent
-- Result: 0 orphans on all 8 links
select 'campaigns.channel_id -> channels' as link, count(*) as orphans
from dbo.campaigns c
left join dbo.channels p on c.channel_id = p.channel_id
where p.channel_id is null and c.channel_id is not null

union all
select 'daily_ad_spend.campaign_id -> campaigns', count(*)
from dbo.daily_ad_spend c
left join dbo.campaigns p on c.campaign_id = p.campaign_id
where p.campaign_id is null and c.campaign_id is not null

union all
select 'touchpoints.customer_id -> customers', count(*)
from dbo.touchpoints c
left join dbo.customers p on c.customer_id = p.customer_id
where p.customer_id is null and c.customer_id is not null

union all
select 'touchpoints.campaign_id -> campaigns', count(*)
from dbo.touchpoints c
left join dbo.campaigns p on c.campaign_id = p.campaign_id
where p.campaign_id is null and c.campaign_id is not null

union all
select 'accounts.customer_id -> customers', count(*)
from dbo.accounts c
left join dbo.customers p on c.customer_id = p.customer_id
where p.customer_id is null and c.customer_id is not null

union all
select 'transactions.account_id -> accounts', count(*)
from dbo.transactions c
left join dbo.accounts p on c.account_id = p.account_id
where p.account_id is null and c.account_id is not null

union all
select 'loans.customer_id -> customers', count(*)
from dbo.loans c
left join dbo.customers p on c.customer_id = p.customer_id
where p.customer_id is null and c.customer_id is not null

union all
select 'repayments.loan_id -> loans', count(*)
from dbo.repayments c
left join dbo.loans p on c.loan_id = p.loan_id
where p.loan_id is null and c.loan_id is not null;


-- XT-03 Event order per customer: signup -> KYC -> account open -> first deposit -> loan
-- One row per customer (customers is collapsed to one row per id first, it repeats 60 ids).
-- Each column counts customers whose events are in the wrong order; dates are compared on the date.
-- loan_before_first_deposit is information only: the dictionary does not forbid it.
-- Result: 81 customers with the first deposit before the first account (triage T-12);
--         only 5,928 of 8,281 customers with an account ever deposited (triage T-17)
with cust as (
    select cus.customer_id,
           min(cus.signup_date) as signup_date,
           min(cus.kyc_date) as kyc_date
    from dbo.customers cus
    group by cus.customer_id
),
acct as (
    select acc.customer_id, min(acc.open_date) as first_open
    from dbo.accounts acc
    group by acc.customer_id
),
dep as (
    select acc.customer_id, min(cast(trs.txn_ts as date)) as first_deposit
    from dbo.transactions trs
    inner join dbo.accounts acc
        on trs.account_id = acc.account_id
    where trs.txn_type = 'deposit'
    group by acc.customer_id
),
loan as (
    select lon.customer_id, min(lon.issue_date) as first_loan
    from dbo.loans lon
    group by lon.customer_id
)
select
    count(*) as customers,
    sum(case when a.customer_id is not null then 1 else 0 end) as with_account,
    sum(case when d.customer_id is not null then 1 else 0 end) as with_deposit,
    sum(case when l.customer_id is not null then 1 else 0 end) as with_loan,
    sum(case when c.kyc_date < c.signup_date then 1 else 0 end) as kyc_before_signup,
    sum(case when a.first_open < c.signup_date then 1 else 0 end) as account_before_signup,
    sum(case when a.first_open < c.kyc_date then 1 else 0 end) as account_before_kyc,
    sum(case when d.first_deposit < a.first_open then 1 else 0 end) as deposit_before_account,
    sum(case when l.first_loan < a.first_open then 1 else 0 end) as loan_before_account,
    sum(case when l.first_loan < d.first_deposit then 1 else 0 end) as loan_before_first_deposit
from cust c
left join acct a on c.customer_id = a.customer_id
left join dep d on c.customer_id = d.customer_id
left join loan l on c.customer_id = l.customer_id;

-- Follow-up (information): loan customers who never made a deposit.
-- The column loan_before_first_deposit cannot see them (a date compared with NULL gives no answer).
-- Result: 0, so none of the 2,353 customers without a deposit has a loan
with dep as (
    select acc.customer_id
    from dbo.transactions trs
    inner join dbo.accounts acc
        on trs.account_id = acc.account_id
    where trs.txn_type = 'deposit'
    group by acc.customer_id
),
loan as (
    select lon.customer_id
    from dbo.loans lon
    group by lon.customer_id
)
select count(*) as loan_customers_without_deposit
from loan l
left join dep d
    on l.customer_id = d.customer_id
where d.customer_id is null;


-- XT-04 Customers per channel: recorded (customers.acquisition_channel) vs first touch (touchpoints)
-- The recorded name is free text, so it is tidied first (lower case, trimmed, spaces and dashes
-- to underscores). Names that still do not match one of the 5 channels stay visible as their own rows.
-- First touch = the earliest touchpoint of the customer (impression or click).
-- Result: 8 non-standard names (triage T-04); recorded and first-touch counts differ on every channel,
--         which is the normal gap between recorded and first-touch channel (Question 3)
with recorded as (
    select lower(replace(replace(ltrim(rtrim(cus.acquisition_channel)), ' ', '_'), '-', '_')) as channel_name,
           count(distinct cus.customer_id) as customers_recorded
    from dbo.customers cus
    group by lower(replace(replace(ltrim(rtrim(cus.acquisition_channel)), ' ', '_'), '-', '_'))
),
first_touch as (
    select tch.customer_id, tch.campaign_id,
           row_number() over (partition by tch.customer_id order by tch.touch_ts, tch.touchpoint_id) as rn
    from dbo.touchpoints tch
),
touched as (
    select ch.channel_name, count(*) as customers_first_touch
    from first_touch ft
    inner join dbo.campaigns cam
        on ft.campaign_id = cam.campaign_id
    inner join dbo.channels ch
        on cam.channel_id = ch.channel_id
    where ft.rn = 1
    group by ch.channel_name
)
select coalesce(r.channel_name, t.channel_name) as channel_name,
       r.customers_recorded,
       t.customers_first_touch,
       r.customers_recorded - t.customers_first_touch as diff
from recorded r
full outer join touched t
    on r.channel_name = t.channel_name
order by channel_name;

-- Customers with no touchpoint at all (they cannot appear in the first-touch column)
-- Result: 40, the uppercase re-signup records (triage T-07)
with cust as (
    select distinct cus.customer_id
    from dbo.customers cus
)
select count(*) as customers_without_touchpoint
from cust c
left join dbo.touchpoints tch
    on c.customer_id = tch.customer_id
where tch.customer_id is null;

-- Follow-up (triage T-04): customers for each pair (tidied recorded name, first-touch channel)
-- Used to map the 8 odd names: each lands 92 to 97 percent in one real channel
-- (ppc and sem in paid_search, fb/ig_ads and social_paid in paid_social, aff_network and affiliates
-- in affiliate, direct/organic in organic, friend_referral in referral). The clean names land
-- 92 to 96 percent in their own channel, so the rest is the normal recorded vs first-touch gap.
with first_touch as (
    select tch.customer_id, tch.campaign_id,
           row_number() over (partition by tch.customer_id order by tch.touch_ts, tch.touchpoint_id) as rn
    from dbo.touchpoints tch
),
first_channel as (
    select ft.customer_id, ch.channel_name as first_touch_channel
    from first_touch ft
    inner join dbo.campaigns cam on ft.campaign_id = cam.campaign_id
    inner join dbo.channels ch on cam.channel_id = ch.channel_id
    where ft.rn = 1
)
select lower(replace(replace(ltrim(rtrim(cus.acquisition_channel)), ' ', '_'), '-', '_')) as recorded_tidied,
       fc.first_touch_channel,
       count(distinct cus.customer_id) as customers
from dbo.customers cus
inner join first_channel fc on cus.customer_id = fc.customer_id
group by lower(replace(replace(ltrim(rtrim(cus.acquisition_channel)), ' ', '_'), '-', '_')),
         fc.first_touch_channel
order by recorded_tidied, customers desc;
