/*
================================================================================
FINTECH CUSTOMER ACQUISITION AND PROFITABILITY ANALYSIS - BUSINESS QUESTIONS
================================================================================
Purpose : The questions behind the headline question, answered with queries on the
          rpt views. Read-only. The findings are written up in
          docs/Business_Questions.md.

Headline question: which acquisition channels bring profitable customers, and how
          should next quarter's marketing budget be reallocated?

Order    : Q0 warm-up, then Q1 to Q5. The headline is answered last, in the Excel
          model (excel/budget_model.xlsx), from the results of these questions.
================================================================================
*/

use NeobankGrowth;
go


/*
================================================================================
Q0 - How big is each group?
================================================================================
*/
-- Q0.1 How many customers does each channel have, and how many funded?
select cus.acquisition_channel,
       count(*) as signups,
       count(fc.customer_id) as funded
from clean.customers cus
left join rpt.v_funded_customers fc on cus.customer_id = fc.customer_id
group by cus.acquisition_channel
order by signups desc;


/*
================================================================================
Q1 - Where do we lose people, and does it differ by channel? (funnel)
================================================================================
*/
-- Q1.1 How many customers reach each stage, per channel?
select acquisition_channel,
       count(*) as signups,
       sum(is_verified) as verified,
       sum(is_funded) as funded,
       sum(is_active) as active
from rpt.v_funnel
group by acquisition_channel
order by acquisition_channel;


-- Q1.2 What share moves from one stage to the next, per channel? (only customers who had enough time to reach the stage)
select acquisition_channel,
       round(1.0 * sum(is_verified) / count(*), 3) as signup_to_verified,
       round(1.0 * sum(case when funded_rate_eligible = 1 and is_verified = 1 then is_funded end)
             / nullif(sum(case when funded_rate_eligible = 1 then is_verified end), 0), 3) as verified_to_funded,
       round(1.0 * sum(case when active_rate_eligible = 1 then is_active end)
             / nullif(sum(case when active_rate_eligible = 1 then is_funded end), 0), 3) as funded_to_active
from rpt.v_funnel
group by acquisition_channel
order by acquisition_channel;


-- Q1.3 Same rates by customer segment.
select segment,
       count(*) as signups,
       round(1.0 * sum(is_verified) / count(*), 3) as signup_to_verified,
       round(1.0 * sum(case when funded_rate_eligible = 1 and is_verified = 1 then is_funded end)
             / nullif(sum(case when funded_rate_eligible = 1 then is_verified end), 0), 3) as verified_to_funded,
       round(1.0 * sum(case when active_rate_eligible = 1 then is_active end)
             / nullif(sum(case when active_rate_eligible = 1 then is_funded end), 0), 3) as funded_to_active
from rpt.v_funnel
group by segment
order by segment;


-- Q1.4 How many days from signup to first deposit, per channel?
select acquisition_channel,
       count(*) as funded_customers,
       round(avg(1.0 * datediff(day, signup_date, first_deposit_date)), 1) as avg_days_to_first_deposit
from rpt.v_funnel
where is_funded = 1
group by acquisition_channel
order by acquisition_channel;


/*
================================================================================
Q2 - Which channels earn back what we paid to win a customer, and how fast? (payback)
================================================================================
*/
-- Q2.1 The scorecard: cost per customer (CAC), 12-month value (LTV), payback month, ROAS.
select acquisition_channel, ad_spend, funded_customers, cac, ltv_12m, ltv_cac, roas,
       payback_month, paid_back_in_12m
from rpt.v_channel_scorecard
order by acquisition_channel;


-- Q2.2 How much does an average customer have earned after each month?
select cv.acquisition_channel, cv.month_no, cv.eligible_customers,
       round(cv.avg_cum_margin, 2) as avg_cum_margin,
       sc.cac
from rpt.v_channel_curve cv
left join rpt.v_channel_scorecard sc on cv.acquisition_channel = sc.acquisition_channel
order by cv.acquisition_channel, cv.month_no;


-- Q2.3 Is the average hiding a few big customers? (average vs median 12-month margin)
with cust as (
    select customer_id, acquisition_channel, sum(margin) as margin_12m
    from rpt.v_customer_month_margin
    group by customer_id, acquisition_channel
    having min(month_complete) = 1
)
select distinct acquisition_channel,
       count(*) over (partition by acquisition_channel) as customers,
       round(avg(margin_12m) over (partition by acquisition_channel), 2) as mean_margin,
       round(percentile_cont(0.5) within group (order by margin_12m) over (partition by acquisition_channel), 2) as median_margin,
       round(avg(case when margin_12m <= 0 then 1.0 else 0 end) over (partition by acquisition_channel), 3) as share_zero_or_negative
from cust
order by acquisition_channel;


-- Q2.4 Do the 41 very large card payments change the LTV ranking?
with elig as (
    select customer_id, acquisition_channel
    from rpt.v_customer_month_margin
    where month_no = 12 and month_complete = 1
),
flagged as (
    select e.acquisition_channel, sum(trs.amount) * 0.003 as flagged_interchange
    from elig e
    inner join rpt.v_funded_customers fc on e.customer_id = fc.customer_id
    inner join clean.accounts acc on e.customer_id = acc.customer_id
    inner join clean.transactions trs on acc.account_id = trs.account_id
    where trs.txn_type = 'card_spend'
      and trs.amount_outlier = 1
      and datediff(day, fc.first_deposit_date, trs.txn_ts) between 0 and 359
    group by e.acquisition_channel
)
select sc.acquisition_channel,
       sc.ltv_12m as ltv_with_large_amounts,
       round(sc.ltv_12m - coalesce(f.flagged_interchange, 0) / sc.eligible_customers_12m, 2) as ltv_without_large_amounts
from rpt.v_channel_scorecard sc
left join flagged f on sc.acquisition_channel = f.acquisition_channel
order by sc.acquisition_channel;


-- Q2.5 12-month margin per customer by channel and segment.
with cust as (
    select m.customer_id, m.acquisition_channel, sum(m.margin) as margin_12m
    from rpt.v_customer_month_margin m
    group by m.customer_id, m.acquisition_channel
    having min(m.month_complete) = 1
)
select c.acquisition_channel, cus.segment,
       count(*) as customers,
       round(avg(c.margin_12m), 2) as avg_margin_12m
from cust c
inner join clean.customers cus on c.customer_id = cus.customer_id
group by c.acquisition_channel, cus.segment
order by c.acquisition_channel, cus.segment;


/*
================================================================================
Q3 - Are we giving too much credit to some channel? (attribution)
================================================================================
*/
-- Q3.1 How many funded customers does each channel get under each way of giving credit?
with credit as (
    select touch_channel as channel,
           sum(credit_first_touch) as first_touch,
           sum(credit_last_touch) as last_touch,
           sum(credit_position) as position_based
    from rpt.v_touch_credit
    group by touch_channel
),
recorded as (
    select acquisition_channel as channel, count(*) as recorded_channel
    from rpt.v_funded_customers
    group by acquisition_channel
)
select coalesce(c.channel, r.channel) as channel,
       r.recorded_channel,
       round(c.first_touch, 1) as first_touch,
       round(c.last_touch, 1) as last_touch,
       round(c.position_based, 1) as position_based
from credit c
full outer join recorded r on c.channel = r.channel
order by 1;


-- Q3.2 How big is the change, in percent?
with credit as (
    select touch_channel as channel, sum(credit_position) as position_based,
           sum(credit_first_touch) as first_touch, sum(credit_last_touch) as last_touch
    from rpt.v_touch_credit
    group by touch_channel
),
recorded as (
    select acquisition_channel as channel, count(*) as recorded_channel
    from rpt.v_funded_customers
    group by acquisition_channel
)
select r.channel,
       r.recorded_channel,
       round(100.0 * (c.first_touch - r.recorded_channel) / r.recorded_channel, 1) as first_touch_change_pct,
       round(100.0 * (c.last_touch - r.recorded_channel) / r.recorded_channel, 1) as last_touch_change_pct,
       round(100.0 * (c.position_based - r.recorded_channel) / r.recorded_channel, 1) as position_change_pct
from recorded r
inner join credit c on r.channel = c.channel
order by r.channel;


-- Q3.3 Does the cost per customer (CAC) change with the model?
with credit as (
    select touch_channel as channel,
           sum(credit_first_touch) as first_touch,
           sum(credit_last_touch) as last_touch,
           sum(credit_position) as position_based
    from rpt.v_touch_credit
    group by touch_channel
)
select sc.acquisition_channel,
       sc.cac as cac_recorded,
       round((sc.ad_spend + sc.kyc_cost) / c.first_touch, 2) as cac_first_touch,
       round((sc.ad_spend + sc.kyc_cost) / c.last_touch, 2) as cac_last_touch,
       round((sc.ad_spend + sc.kyc_cost) / c.position_based, 2) as cac_position
from rpt.v_channel_scorecard sc
inner join credit c on sc.acquisition_channel = c.channel
where sc.cac is not null
order by sc.acquisition_channel;


-- Q3.4 How many clicks does a funded customer have before the first deposit?
with per_customer as (
    select customer_id, max(clicks_total) as clicks
    from rpt.v_touch_credit
    group by customer_id
)
select clicks, count(*) as customers
from per_customer
group by clicks
order by clicks;


/*
================================================================================
Q4 - Which campaigns waste money? (campaigns)
================================================================================
*/
-- Q4.1 Cost per customer of every campaign, most expensive first.
select campaign_name, channel_name, total_spend, credited_customers, campaign_cac,
       channel_median_cac, cac_vs_median, is_wasteful
from rpt.v_campaign_cac
order by campaign_cac desc;


-- Q4.2 How much of its channel's spend do the flagged campaigns hold?
with channel_spend as (
    select channel_name, sum(total_spend) as channel_spend
    from rpt.v_campaign_cac
    group by channel_name
)
select c.channel_name, c.campaign_name, c.total_spend,
       round(100.0 * c.total_spend / cs.channel_spend, 1) as share_of_channel_spend_pct,
       c.credited_customers, c.campaign_cac, c.channel_median_cac
from rpt.v_campaign_cac c
inner join channel_spend cs on c.channel_name = cs.channel_name
where c.is_wasteful = 1;


-- Q4.3 How much spend happened on days with zero impressions?
select campaign_name, channel_name, total_spend, zero_impression_spend, zero_impression_share
from rpt.v_campaign_cac
where zero_impression_spend > 0
order by zero_impression_spend desc;


-- Q4.4 Seasonality: is the cost per customer higher in some months? (index of 1.0 = the channel's average month)
select channel_name, month_start, ad_spend, credited_customers,
       round(ad_spend / nullif(credited_customers, 0), 2) as monthly_cac,
       round((ad_spend / nullif(credited_customers, 0))
             / avg(ad_spend / nullif(credited_customers, 0)) over (partition by channel_name), 2) as seasonality_index
from rpt.v_budget_inputs
order by channel_name, month_start;


/*
================================================================================
Q5 - Which channels bring customers who do not repay? (credit risk)
================================================================================
*/
-- Q5.1 Delinquency and default rate per channel (seasoned loans only)
select acquisition_channel,
       count(*) as loans,
       sum(window_complete) as seasoned_loans,
       round(1.0 * sum(is_delinquent_30) / nullif(sum(window_complete), 0), 3) as delinquency_rate,
       round(1.0 * sum(is_default_90) / nullif(sum(window_complete), 0), 3) as default_rate,
       round(1.0 * sum(is_early_default) / nullif(sum(window_complete), 0), 3) as early_default_rate,
       round(sum(credit_loss), 0) as credit_loss
from rpt.v_loan_dpd
group by acquisition_channel
order by acquisition_channel;


-- Q5.2 Early defaults by channel and segment.
select acquisition_channel, segment, seasoned_loans, early_default_rate, low_sample
from rpt.v_credit_by_segment
order by acquisition_channel, segment;


-- Q5.3 12-month value before and after credit loss.
select acquisition_channel, cac, ltv_12m, credit_loss_per_customer, risk_adj_ltv_12m,
       ltv_cac, risk_adj_ltv_cac
from rpt.v_channel_scorecard
order by acquisition_channel;


-- Q5.4 Loans per channel: how many customers take one, and what kind?
select acquisition_channel, grade,
       count(*) as loans,
       round(avg(principal), 0) as avg_principal,
       round(avg(apr), 1) as avg_apr
from rpt.v_loan_dpd
group by acquisition_channel, grade
order by acquisition_channel, grade;


-- Q5.5 How many loans are too young to judge (not seasoned), per channel?
select acquisition_channel,
       count(*) as loans,
       sum(1 - window_complete) as not_seasoned,
       round(100.0 * sum(1 - window_complete) / count(*), 1) as not_seasoned_pct
from rpt.v_loan_dpd
group by acquisition_channel
order by acquisition_channel;


/*
================================================================================
HEADLINE - Inputs for the budget model
================================================================================
*/
-- H.1 Baseline budget (July to September 2026) and the value per customer, per channel.
select channel_name,
       max(baseline_quarter_spend) as baseline_quarter_spend,
       max(risk_adj_ltv_12m) as risk_adj_ltv_12m
from rpt.v_budget_inputs
group by channel_name
order by channel_name;


-- H.2 Monthly spend and customers per channel (the 24 points per channel the model uses)
select channel_name, month_start, ad_spend, credited_customers
from rpt.v_budget_inputs
order by channel_name, month_start;
