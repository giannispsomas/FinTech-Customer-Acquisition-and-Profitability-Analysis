/*
================================================================================
FINTECH CUSTOMER ACQUISITION AND PROFITABILITY ANALYSIS - REPORTING VIEWS
================================================================================
Purpose   : Define every metric once, as a reporting view in schema rpt, for the
            EDA, the Excel model and the Power BI report. The views only read the
            clean layer (and each other); they never change data.

Structure : PART 1  Setup
            PART 2  Customer and margin views     steps 01-02
            PART 3  Funnel, attribution, credit   steps 03-05
            PART 4  Channel and campaign views    steps 06-10

Each step ends with its checks. Each view uses the views before it, so the steps
must run in order.

How to run
    Run the whole script once, top to bottom (F5). Every view is created with
    create or alter, so the script can be re-run. The GO lines are required: a
    view must be the first statement of its batch.
================================================================================
*/

use NeobankGrowth;
go

if schema_id('rpt') is null exec('create schema rpt');
go


/*
================================================================================
PART 2 - CUSTOMER AND MARGIN VIEWS
================================================================================
The funded customers and what each one earns the company, month by month.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 01 | rpt.v_funded_customers                                       (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per funded customer (5,928): a customer with at least one
--           deposit.
-- COLUMNS : customer_id, acquisition_channel, signup_date, first_deposit_date
-- SOURCE  : clean.customers, clean.accounts, clean.transactions
-- RULES   : - The first deposit date ignores deposits dated before the account
--             opened (txn_before_account_open = 1, T-12). No customer is lost
--             by this: every customer with a flagged deposit also has a clean
--             one.
-- USED BY : almost every other view.

create or alter view rpt.v_funded_customers as
with cte_first_deposits as (
	select
        acc.customer_id,
        min(cast(trs.txn_ts as date)) as first_deposit_date
	from clean.accounts acc
	inner join clean.transactions trs
		on acc.account_id = trs.account_id
	where trs.txn_type = 'deposit' and trs.txn_before_account_open = 0
	group by acc.customer_id
)
select
    cus.customer_id,
    cus.acquisition_channel,
    cus.signup_date,
    dep.first_deposit_date
from clean.customers cus
inner join cte_first_deposits dep
	on cus.customer_id = dep.customer_id;
go

-- Checks: 5,928 rows, one row per customer, no NULL first deposit date
select count(*) as total_rows,
       count(distinct customer_id) as distinct_customers,
       sum(case when first_deposit_date is null then 1 else 0 end) as null_dates
from rpt.v_funded_customers;
go

--------------------------------------------------------------------------------
-- STEP 02 | rpt.v_customer_month_margin                                  (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per funded customer per 30-day month (1 to 12), counted
--           from the first deposit. Margin = interchange + origination fee +
--           loan interest - cost of funds - servicing.
-- COLUMNS : customer_id, acquisition_channel, month_no, interchange,
--           origination_fee, loan_interest, cost_of_funds, servicing, margin,
--           month_complete
-- SOURCE  : rpt.v_funded_customers, clean.transactions, clean.accounts,
--           clean.loans, clean.repayments, clean.assumptions
-- RULES   : - Month m covers days 30(m-1) to 30m-1 after the first deposit.
--             Only days 0 to 359 count.
--           - Every funded customer has all 12 rows. Months with no activity
--             are zero (grid plus coalesce).
--           - Interchange = interchange rate x card spend. Servicing =
--             servicing cost in every month with at least one transaction.
--             Origination fee = fee rate x principal, in the month the loan is
--             issued.
--           - Loan interest: repayments has no interest column, so it is
--             rebuilt from the loan schedule (fixed installment, apr / 12 a
--             month). Interest of installment k = opening balance x apr / 12,
--             earned in proportion to amount_paid / amount_due and counted in
--             the month of paid_date. Unpaid installments earn nothing.
--           - Opening balance of installment k = principal x ((1+r)^n -
--             (1+r)^(k-1)) / ((1+r)^n - 1), with r = apr / 12 and n = term in
--             months.
--           - Cost of funds = opening balance x cost of funds rate / 12,
--             counted in the month of the due date, paid or not. The 29 loans
--             with no installments yet have none.
--           - month_complete = 1 when the data covers all 30 days of the month.
--             Averages by month use month_complete = 1 only.
--           - Credit loss is not here (see rpt.v_loan_dpd).
-- USED BY : rpt.v_channel_curve, rpt.v_channel_scorecard.

create or alter view rpt.v_customer_month_margin as
with asm as (
    select
        max(case when assumption_key = 'interchange_rate'                then assumption_value end) as interchange_rate,
        max(case when assumption_key = 'origination_fee_rate'            then assumption_value end) as fee_rate,
        max(case when assumption_key = 'loan_cost_of_funds_annual'       then assumption_value end) as cof_rate,
        max(case when assumption_key = 'servicing_cost_per_active_month' then assumption_value end) as servicing_cost,
        max(assumption_date) as as_of_date
    from clean.assumptions
),
-- Piece 1: the grid. Every funded customer x months 1 to 12
grid as (
    select fc.customer_id, fc.acquisition_channel, fc.first_deposit_date, m.month_no
    from rpt.v_funded_customers fc
    cross join (values (1), (2), (3), (4), (5), (6), (7), (8), (9), (10), (11), (12)) as m(month_no)
),
-- Piece 2: card spend and active months (one row per customer-month with a transaction)
activity as (
    select acc.customer_id,
           datediff(day, fc.first_deposit_date, trs.txn_ts) / 30 + 1 as month_no,
           sum(case when trs.txn_type = 'card_spend' then trs.amount else 0 end) as card_spend
    from clean.transactions trs
    inner join clean.accounts acc on trs.account_id = acc.account_id
    inner join rpt.v_funded_customers fc on acc.customer_id = fc.customer_id
    where datediff(day, fc.first_deposit_date, trs.txn_ts) between 0 and 359
    group by acc.customer_id,
             datediff(day, fc.first_deposit_date, trs.txn_ts) / 30 + 1
),
-- Piece 3: principal issued, by the month of issue
fee as (
    select lns.customer_id,
           datediff(day, fc.first_deposit_date, lns.issue_date) / 30 + 1 as month_no,
           sum(lns.principal) as principal_issued
    from clean.loans lns
    inner join rpt.v_funded_customers fc on lns.customer_id = fc.customer_id
    where datediff(day, fc.first_deposit_date, lns.issue_date) between 0 and 359
    group by lns.customer_id,
             datediff(day, fc.first_deposit_date, lns.issue_date) / 30 + 1
),
-- Piece 4 and 5, step 1: every installment with the balance still owed at its start
schedule as (
    select lns.customer_id,
           rep.due_date,
           rep.paid_date,
           ob.opening_balance,
           ob.opening_balance * (lns.apr / 1200.0) * rep.amount_paid / rep.amount_due as interest_earned,
           ob.opening_balance * asm.cof_rate / 12.0 as cost_of_funds
    from clean.repayments rep
    inner join clean.loans lns on rep.loan_id = lns.loan_id
    cross join asm
    cross apply (
        select lns.principal
               * (power(1 + lns.apr / 1200.0, lns.term_months) - power(1 + lns.apr / 1200.0, rep.installment_no - 1))
               / (power(1 + lns.apr / 1200.0, lns.term_months) - 1) as opening_balance
    ) ob
),
-- Piece 4, step 2: interest by the month of paid_date
interest as (
    select sch.customer_id,
           datediff(day, fc.first_deposit_date, sch.paid_date) / 30 + 1 as month_no,
           sum(sch.interest_earned) as loan_interest
    from schedule sch
    inner join rpt.v_funded_customers fc on sch.customer_id = fc.customer_id
    where sch.paid_date is not null
      and datediff(day, fc.first_deposit_date, sch.paid_date) between 0 and 359
    group by sch.customer_id,
             datediff(day, fc.first_deposit_date, sch.paid_date) / 30 + 1
),
-- Piece 5, step 2: cost of funds by the month of due_date
funds as (
    select sch.customer_id,
           datediff(day, fc.first_deposit_date, sch.due_date) / 30 + 1 as month_no,
           sum(sch.cost_of_funds) as cost_of_funds
    from schedule sch
    inner join rpt.v_funded_customers fc on sch.customer_id = fc.customer_id
    where datediff(day, fc.first_deposit_date, sch.due_date) between 0 and 359
    group by sch.customer_id,
             datediff(day, fc.first_deposit_date, sch.due_date) / 30 + 1
),
-- Piece 6: put the pieces on the grid, zero where nothing happened
parts as (
    select g.customer_id,
           g.acquisition_channel,
           g.month_no,
           round(coalesce(act.card_spend, 0) * asm.interchange_rate, 4)       as interchange,
           round(coalesce(f.principal_issued, 0) * asm.fee_rate, 4)           as origination_fee,
           round(coalesce(i.loan_interest, 0), 4)                             as loan_interest,
           round(coalesce(fu.cost_of_funds, 0), 4)                            as cost_of_funds,
           case when act.customer_id is not null then asm.servicing_cost else 0 end as servicing,
           case when datediff(day, g.first_deposit_date, asm.as_of_date) >= 30 * g.month_no - 1
                then 1 else 0 end                                             as month_complete
    from grid g
    cross join asm
    left join activity act on g.customer_id = act.customer_id and g.month_no = act.month_no
    left join fee f        on g.customer_id = f.customer_id   and g.month_no = f.month_no
    left join interest i   on g.customer_id = i.customer_id   and g.month_no = i.month_no
    left join funds fu     on g.customer_id = fu.customer_id  and g.month_no = fu.month_no
)
select customer_id,
       acquisition_channel,
       month_no,
       interchange,
       origination_fee,
       loan_interest,
       cost_of_funds,
       servicing,
       interchange + origination_fee + loan_interest - cost_of_funds - servicing as margin,
       month_complete
from parts;
go

-- Checks
-- 1. Grid: 71,136 rows = 5,928 customers x 12 months, no duplicate customer-month
select count(*) as total_rows,
       count(distinct customer_id) as customers,
       count(distinct concat(customer_id, '-', month_no)) as distinct_customer_months,
       min(month_no) as min_month, max(month_no) as max_month
from rpt.v_customer_month_margin;

-- 2. Totals against direct calculations (each pair should match)
select
    (select sum(interchange) from rpt.v_customer_month_margin) as view_interchange,
    (select sum(case when trs.txn_type = 'card_spend' then trs.amount else 0 end) * 0.003
     from clean.transactions trs
     inner join clean.accounts acc on trs.account_id = acc.account_id
     inner join rpt.v_funded_customers fc on acc.customer_id = fc.customer_id
     where datediff(day, fc.first_deposit_date, trs.txn_ts) between 0 and 359) as direct_interchange,
    (select sum(origination_fee) from rpt.v_customer_month_margin) as view_fee,
    (select sum(lns.principal) * 0.03
     from clean.loans lns
     inner join rpt.v_funded_customers fc on lns.customer_id = fc.customer_id
     where datediff(day, fc.first_deposit_date, lns.issue_date) between 0 and 359) as direct_fee;

-- 3. Servicing: 0.40 x number of active customer-months (27,640 from piece 2)
select sum(servicing) as view_servicing, 27640 * 0.40 as expected_servicing
from rpt.v_customer_month_margin;

-- 4. Interest logic: on loans with the full schedule, scheduled interest = installments x amount_due - principal
select count(*) as full_schedule_loans,
       sum(abs(si.sched_interest - (si.n * si.amount_due - si.principal))) as total_abs_difference
from (
    select lns.loan_id, lns.principal, lns.term_months, max(rep.amount_due) as amount_due, count(*) as n,
           sum(lns.principal
               * (power(1 + lns.apr / 1200.0, lns.term_months) - power(1 + lns.apr / 1200.0, rep.installment_no - 1))
               / (power(1 + lns.apr / 1200.0, lns.term_months) - 1) * (lns.apr / 1200.0)) as sched_interest
    from clean.loans lns
    inner join clean.repayments rep on lns.loan_id = rep.loan_id
    group by lns.loan_id, lns.principal, lns.term_months
    having count(*) = lns.term_months
) si;

-- 5. First look: average 12-month margin per customer by channel, customers with all 12 months complete
select acquisition_channel,
       count(distinct customer_id) as customers,
       round(sum(margin) / count(distinct customer_id), 2) as margin_per_customer_12m
from rpt.v_customer_month_margin
where customer_id in (select customer_id from rpt.v_customer_month_margin
                      where month_no = 12 and month_complete = 1)
group by acquisition_channel
order by acquisition_channel;
go


/*
================================================================================
PART 3 - FUNNEL, ATTRIBUTION AND CREDIT
================================================================================
Where customers drop out, which channel gets the credit, and which loans go bad.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 03 | rpt.v_funnel                                                 (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per customer (10,000) with a 0/1 flag for each funnel
--           stage.
-- COLUMNS : customer_id, acquisition_channel, segment, signup_date,
--           is_verified, kyc_date_missing, is_funded, first_deposit_date,
--           is_active, funded_rate_eligible, active_rate_eligible
-- SOURCE  : clean.customers, rpt.v_funded_customers, clean.transactions,
--           clean.accounts, clean.assumptions
-- RULES   : - Stages: signup, verified (kyc_status = verified), funded (first
--             deposit), active (any transaction in days 31 to 90 after the
--             first deposit; a withdrawal counts).
--           - A verified customer with a missing KYC date stays in the funnel
--             (kyc_date_missing = 1).
--           - Rates use only customers with a full observation window:
--             funded_rate_eligible = signup on or before the as-of date minus
--             30 days; active_rate_eligible = first deposit on or before the
--             as-of date minus 90 days.
-- USED BY : Question 1 (funnel by channel and segment).

create or alter view rpt.v_funnel as
with asm as (
    select max(assumption_date) as as_of_date
    from clean.assumptions
),
active_customers as (
    select distinct acc.customer_id
    from clean.transactions trs
    inner join clean.accounts acc on trs.account_id = acc.account_id
    inner join rpt.v_funded_customers fc on acc.customer_id = fc.customer_id
    where datediff(day, fc.first_deposit_date, trs.txn_ts) between 31 and 90
)
select cus.customer_id,
       cus.acquisition_channel,
       cus.segment,
       cus.signup_date,
       case when cus.kyc_status = 'verified' then 1 else 0 end            as is_verified,
       cus.kyc_date_missing,
       case when fc.customer_id is not null then 1 else 0 end             as is_funded,
       fc.first_deposit_date,
       case when act.customer_id is not null then 1 else 0 end            as is_active,
       case when cus.signup_date <= dateadd(day, -30, asm.as_of_date) then 1 else 0 end       as funded_rate_eligible,
       case when fc.first_deposit_date <= dateadd(day, -90, asm.as_of_date) then 1 else 0 end as active_rate_eligible
from clean.customers cus
cross join asm
left join rpt.v_funded_customers fc on cus.customer_id = fc.customer_id
left join active_customers act on cus.customer_id = act.customer_id;
go

-- Checks
-- 1. 10,000 rows, 10,000 distinct customers, 8,281 verified, 5,928 funded; active never without funded
select count(*) as total_rows,
       count(distinct customer_id) as distinct_customers,
       sum(is_verified) as verified,
       sum(is_funded) as funded,
       sum(is_active) as active,
       sum(case when is_active = 1 and is_funded = 0 then 1 else 0 end) as active_not_funded
from rpt.v_funnel;

-- 2. Funnel by channel, eligible customers only
select acquisition_channel,
       count(*) as signups,
       sum(is_verified) as verified,
       round(1.0 * sum(is_verified) / count(*), 3) as verified_rate,
       round(1.0 * sum(case when funded_rate_eligible = 1 and is_verified = 1 then is_funded end)
             / nullif(sum(case when funded_rate_eligible = 1 then is_verified end), 0), 3) as verified_to_funded,
       round(1.0 * sum(case when active_rate_eligible = 1 then is_active end)
             / nullif(sum(case when active_rate_eligible = 1 then is_funded end), 0), 3) as funded_to_active
from rpt.v_funnel
group by acquisition_channel
order by acquisition_channel;
go

--------------------------------------------------------------------------------
-- STEP 04 | rpt.v_loan_dpd                                               (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per loan (2,290) with days past due, default flags and
--           credit loss.
-- COLUMNS : loan_id, customer_id, acquisition_channel, segment, grade,
--           issue_date, principal, apr, term_months, window_complete,
--           worst_dpd, is_delinquent_30, is_default_90, is_early_default,
--           first_default_installment, credit_loss
-- SOURCE  : clean.loans, clean.repayments, clean.customers, clean.assumptions
-- RULES   : - DPD of an installment = days between the due date and the day it
--             was cleared, or the as-of date (2026-09-30) if it is not cleared.
--             Never below 0. A partial payment does not clear an installment.
--           - worst_dpd is the highest DPD of the loan. Delinquent = 30 or
--             more, default = 90 or more, early default = a 90+ DPD installment
--             due within 6 months of issue.
--           - The flags and credit_loss are filled only for seasoned loans
--             (window_complete = 1). Unseasoned loans get NULL.
--           - credit_loss = loss given default (0.90) x the scheduled principal
--             still owed at the start of the first 90+ DPD installment; 0 for
--             seasoned loans that did not default.
-- USED BY : rpt.v_credit_by_segment, rpt.v_channel_scorecard, Question 5.

create or alter view rpt.v_loan_dpd as
with asm as (
    select
        max(case when assumption_key = 'loss_given_default' then assumption_value end) as lgd,
        max(assumption_date) as as_of_date
    from clean.assumptions
),
installments as (
    select lns.loan_id,
           lns.issue_date,
           rep.installment_no,
           rep.due_date,
           case when rep.paid_date is not null and rep.amount_paid >= rep.amount_due - 0.005
                then rep.paid_date else asm.as_of_date end as end_date,
           lns.principal
               * (power(1 + lns.apr / 1200.0, lns.term_months) - power(1 + lns.apr / 1200.0, rep.installment_no - 1))
               / (power(1 + lns.apr / 1200.0, lns.term_months) - 1) as opening_balance
    from clean.repayments rep
    inner join clean.loans lns on rep.loan_id = lns.loan_id
    cross join asm
),
dpd as (
    select inst.*,
           case when datediff(day, inst.due_date, inst.end_date) > 0
                then datediff(day, inst.due_date, inst.end_date) else 0 end as dpd
    from installments inst
),
loan_summary as (
    select loan_id,
           max(dpd) as worst_dpd,
           min(case when dpd >= 90 then installment_no end) as first_default_installment,
           max(case when dpd >= 90 and due_date <= dateadd(month, 6, issue_date) then 1 else 0 end) as early_default
    from dpd
    group by loan_id
)
select lns.loan_id,
       lns.customer_id,
       cus.acquisition_channel,
       cus.segment,
       lns.grade,
       lns.issue_date,
       lns.principal,
       lns.apr,
       lns.term_months,
       lns.window_complete,
       coalesce(ls.worst_dpd, 0) as worst_dpd,
       case when lns.window_complete = 1 then case when coalesce(ls.worst_dpd, 0) >= 30 then 1 else 0 end end as is_delinquent_30,
       case when lns.window_complete = 1 then case when coalesce(ls.worst_dpd, 0) >= 90 then 1 else 0 end end as is_default_90,
       case when lns.window_complete = 1 then coalesce(ls.early_default, 0) end                                 as is_early_default,
       ls.first_default_installment,
       case when lns.window_complete = 1
            then round(coalesce(asm.lgd * fd.opening_balance, 0), 2) end                                        as credit_loss
from clean.loans lns
cross join asm
inner join clean.customers cus on lns.customer_id = cus.customer_id
left join loan_summary ls on lns.loan_id = ls.loan_id
left join dpd fd on ls.loan_id = fd.loan_id and ls.first_default_installment = fd.installment_no;
go

-- Checks
-- 1. 2,290 rows, one per loan; 1,587 seasoned and 703 not; flags only on seasoned loans
select count(*) as total_rows,
       count(distinct loan_id) as distinct_loans,
       sum(window_complete) as seasoned,
       sum(case when window_complete = 0 and is_default_90 is not null then 1 else 0 end) as flags_on_unseasoned
from rpt.v_loan_dpd;

-- 2. Order of the flags: early default is a subset of default, default a subset of delinquent
select sum(is_delinquent_30) as delinquent,
       sum(is_default_90) as defaults,
       sum(is_early_default) as early_defaults,
       sum(case when is_default_90 = 1 and is_delinquent_30 = 0 then 1 else 0 end) as default_not_delinquent,
       sum(case when is_early_default = 1 and is_default_90 = 0 then 1 else 0 end) as early_not_default,
       sum(case when is_default_90 = 1 and credit_loss = 0 then 1 else 0 end) as default_without_loss,
       sum(case when is_default_90 = 0 and credit_loss > 0 then 1 else 0 end) as loss_without_default
from rpt.v_loan_dpd;

-- 3. Default rate by channel (seasoned loans)
select acquisition_channel,
       sum(window_complete) as seasoned_loans,
       round(1.0 * sum(is_default_90) / nullif(sum(window_complete), 0), 3) as default_rate,
       round(sum(credit_loss), 0) as credit_loss
from rpt.v_loan_dpd
group by acquisition_channel
order by acquisition_channel;
go

--------------------------------------------------------------------------------
-- STEP 05 | rpt.v_touch_credit                                           (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per funded customer per qualifying click, plus one
--           'unattributed' row for each funded customer with no click.
-- COLUMNS : customer_id, recorded_channel, touchpoint_id, campaign_id,
--           touch_channel, touch_ts, click_no, clicks_total,
--           credit_first_touch, credit_last_touch, credit_position
-- SOURCE  : clean.touchpoints, clean.campaigns, clean.channels,
--           clean.transactions, clean.accounts, rpt.v_funded_customers
-- RULES   : - Clicks only, and only before the first deposit moment. Clicks are
--             ordered by time, ties by touchpoint_id.
--           - First touch: 1 credit to the first click. Last touch: 1 credit to
--             the last click. Position-based: 1 click = 1.0, 2 clicks = 0.5
--             each, 3 or more = 0.4 first, 0.4 last, 0.2 shared by the middle
--             clicks.
--           - touch_channel is the channel of the clicked campaign. Each credit
--             column adds up to 5,928, the number of funded customers.
-- USED BY : rpt.v_campaign_cac, rpt.v_budget_inputs, Question 3.

create or alter view rpt.v_touch_credit as
with first_deposits as (
    select acc.customer_id, min(trs.txn_ts) as first_deposit_ts
    from clean.accounts acc
    inner join clean.transactions trs on acc.account_id = trs.account_id
    where trs.txn_type = 'deposit' and trs.txn_before_account_open = 0
    group by acc.customer_id
),
clicks as (
    select tch.touchpoint_id,
           tch.customer_id,
           tch.campaign_id,
           tch.touch_ts,
           row_number() over (partition by tch.customer_id order by tch.touch_ts, tch.touchpoint_id) as click_no,
           count(*)     over (partition by tch.customer_id) as clicks_total
    from clean.touchpoints tch
    inner join first_deposits fd on tch.customer_id = fd.customer_id
    where tch.touch_type = 'click'
      and tch.touch_ts < fd.first_deposit_ts
),
attributed as (
    select clk.customer_id,
           clk.touchpoint_id,
           clk.campaign_id,
           ch.channel_name as touch_channel,
           clk.touch_ts,
           clk.click_no,
           clk.clicks_total,
           case when clk.click_no = 1 then 1.0 else 0.0 end                    as credit_first_touch,
           case when clk.click_no = clk.clicks_total then 1.0 else 0.0 end     as credit_last_touch,
           case when clk.clicks_total = 1 then 1.0
                when clk.clicks_total = 2 then 0.5
                when clk.click_no = 1 or clk.click_no = clk.clicks_total then 0.4
                else 0.2 / (clk.clicks_total - 2) end                          as credit_position
    from clicks clk
    inner join clean.campaigns cam on clk.campaign_id = cam.campaign_id
    inner join clean.channels ch on cam.channel_id = ch.channel_id
),
unattributed as (
    select fc.customer_id,
           cast(null as int)       as touchpoint_id,
           cast(null as int)       as campaign_id,
           cast('unattributed' as nvarchar(50)) as touch_channel,
           cast(null as datetime2) as touch_ts,
           cast(null as bigint)    as click_no,
           cast(0 as int)          as clicks_total,
           1.0 as credit_first_touch,
           1.0 as credit_last_touch,
           1.0 as credit_position
    from rpt.v_funded_customers fc
    where fc.customer_id not in (select customer_id from clicks)
)
select fc.customer_id,
       fc.acquisition_channel as recorded_channel,
       cr.touchpoint_id,
       cr.campaign_id,
       cr.touch_channel,
       cr.touch_ts,
       cr.click_no,
       cr.clicks_total,
       cr.credit_first_touch,
       cr.credit_last_touch,
       cr.credit_position
from rpt.v_funded_customers fc
inner join (
    select * from attributed
    union all
    select * from unattributed
) cr on fc.customer_id = cr.customer_id;
go

-- Checks
-- 1. Reconciliation: every credit column adds up to 5,928 funded customers
select count(distinct customer_id) as customers,
       round(sum(credit_first_touch), 4) as first_touch_total,
       round(sum(credit_last_touch), 4) as last_touch_total,
       round(sum(credit_position), 4) as position_total
from rpt.v_touch_credit;

-- 2. Credit by channel under each model, next to the recorded channel
with credit as (
    select touch_channel as channel,
           sum(credit_first_touch) as first_touch,
           sum(credit_last_touch) as last_touch,
           sum(credit_position) as position_based
    from rpt.v_touch_credit
    group by touch_channel
),
recorded as (
    select acquisition_channel as channel, count(*) as recorded
    from rpt.v_funded_customers
    group by acquisition_channel
)
select coalesce(c.channel, r.channel) as channel,
       r.recorded,
       round(c.first_touch, 1) as first_touch,
       round(c.last_touch, 1) as last_touch,
       round(c.position_based, 1) as position_based
from credit c
full outer join recorded r on c.channel = r.channel
order by 1;
go


/*
================================================================================
PART 4 - CHANNEL AND CAMPAIGN VIEWS
================================================================================
The channel scorecard, credit by segment, campaign cost and the budget inputs.
================================================================================
*/

--------------------------------------------------------------------------------
-- STEP 06 | rpt.v_channel_curve                                          (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per channel and month since the first deposit: the average
--           cumulative margin per customer.
-- COLUMNS : acquisition_channel, month_no, eligible_customers, avg_cum_margin,
--           avg_cum_revenue
-- SOURCE  : rpt.v_customer_month_margin
-- RULES   : - Month k uses only customers whose month k is complete, so late
--             months are not dragged down by customers who have not had time to
--             reach them. eligible_customers is the number behind each point.
--           - Revenue = interchange + origination fee + loan interest (before
--             costs).
-- USED BY : rpt.v_channel_scorecard, the payback line chart.

create or alter view rpt.v_channel_curve as
with cum as (
    select customer_id,
           acquisition_channel,
           month_no,
           month_complete,
           sum(margin) over (partition by customer_id order by month_no rows unbounded preceding) as cum_margin,
           sum(interchange + origination_fee + loan_interest)
               over (partition by customer_id order by month_no rows unbounded preceding) as cum_revenue
    from rpt.v_customer_month_margin
)
select acquisition_channel,
       month_no,
       count(*) as eligible_customers,
       round(avg(cum_margin), 4) as avg_cum_margin,
       round(avg(cum_revenue), 4) as avg_cum_revenue
from cum
where month_complete = 1
group by acquisition_channel, month_no;
go

-- Checks
-- 1. 5 channels x 12 months = 60 rows; eligible customers never grow with the month number
select count(*) as total_rows,
       count(distinct e.acquisition_channel) as channels,
       sum(case when e.eligible_customers > p.eligible_customers then 1 else 0 end) as months_with_more_customers_than_before
from rpt.v_channel_curve e
left join rpt.v_channel_curve p
       on e.acquisition_channel = p.acquisition_channel and e.month_no = p.month_no + 1;

-- 2. Cumulative margin at month 1, 6 and 12 per channel
select acquisition_channel, month_no, eligible_customers, round(avg_cum_margin, 2) as avg_cum_margin
from rpt.v_channel_curve
where month_no in (1, 6, 12)
order by acquisition_channel, month_no;
go

--------------------------------------------------------------------------------
-- STEP 07 | rpt.v_channel_scorecard                                      (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per channel: cost to acquire, 12-month value, payback and
--           ROAS, before and after credit loss.
-- COLUMNS : acquisition_channel, ad_spend, funded_customers, kyc_decisions,
--           kyc_cost, cac, ad_only_cac, eligible_customers_12m, ltv_12m,
--           revenue_12m, ltv_cac, roas, payback_month, paid_back_in_12m,
--           credit_loss_per_customer, risk_adj_ltv_12m, risk_adj_ltv_cac
-- SOURCE  : clean.daily_ad_spend, clean.campaigns, clean.channels,
--           clean.customers, rpt.v_funded_customers,
--           rpt.v_customer_month_margin, rpt.v_channel_curve, rpt.v_loan_dpd,
--           clean.assumptions
-- RULES   : - CAC = (ad spend + KYC cost) / funded customers over the whole
--             period. KYC cost = 2.50 x customers with a KYC decision (verified
--             or rejected). ad_only_cac = ad spend / funded customers.
--           - Organic has no ad spend, so its CAC, ROAS, LTV/CAC and payback
--             are NULL.
--           - ltv_12m = average cumulative margin at month 12, over the
--             customers with a complete month 12, before credit loss. roas =
--             revenue_12m / ad_only_cac.
--           - payback_month = first month where the average cumulative margin
--             reaches CAC. NULL means not paid back within 12 months.
--           - credit_loss_per_customer = credit loss on the seasoned loans of
--             the same customers / customers. risk_adj_ltv_12m = ltv_12m -
--             credit_loss_per_customer. Loans issued after 2026-03-31 carry no
--             loss, so the loss is a floor.
-- USED BY : Questions 2 and 5, rpt.v_budget_inputs.

create or alter view rpt.v_channel_scorecard as
with asm as (
    select max(case when assumption_key = 'kyc_cost_per_check' then assumption_value end) as kyc_cost_per_check
    from clean.assumptions
),
spend as (
    select ch.channel_name, sum(sp.spend) as ad_spend
    from clean.daily_ad_spend sp
    inner join clean.campaigns cam on sp.campaign_id = cam.campaign_id
    inner join clean.channels ch on cam.channel_id = ch.channel_id
    group by ch.channel_name
),
funded as (
    select acquisition_channel, count(*) as funded_customers
    from rpt.v_funded_customers
    group by acquisition_channel
),
kyc as (
    select acquisition_channel,
           sum(case when kyc_status in ('verified', 'rejected') then 1 else 0 end) as kyc_decisions
    from clean.customers
    group by acquisition_channel
),
eligible as (
    select customer_id, acquisition_channel
    from rpt.v_customer_month_margin
    where month_no = 12 and month_complete = 1
),
loss as (
    select e.acquisition_channel, sum(coalesce(lo.credit_loss, 0)) as credit_loss
    from eligible e
    left join rpt.v_loan_dpd lo on e.customer_id = lo.customer_id and lo.window_complete = 1
    group by e.acquisition_channel
),
base as (
    select ch.channel_name as acquisition_channel,
           coalesce(spd.ad_spend, 0) as ad_spend,
           fnd.funded_customers,
           k.kyc_decisions,
           k.kyc_decisions * asm.kyc_cost_per_check as kyc_cost,
           case when ch.has_spend = 1
                then (spd.ad_spend + k.kyc_decisions * asm.kyc_cost_per_check) / fnd.funded_customers end as cac,
           case when ch.has_spend = 1 then spd.ad_spend / fnd.funded_customers end as ad_only_cac,
           cv.eligible_customers as eligible_customers_12m,
           cv.avg_cum_margin as ltv_12m,
           cv.avg_cum_revenue as revenue_12m,
           ls.credit_loss / cv.eligible_customers as credit_loss_per_customer
    from clean.channels ch
    cross join asm
    left join spend spd on ch.channel_name = spd.channel_name
    left join funded fnd on ch.channel_name = fnd.acquisition_channel
    left join kyc k on ch.channel_name = k.acquisition_channel
    left join rpt.v_channel_curve cv on ch.channel_name = cv.acquisition_channel and cv.month_no = 12
    left join loss ls on ch.channel_name = ls.acquisition_channel
)
select b.acquisition_channel,
       round(b.ad_spend, 2) as ad_spend,
       b.funded_customers,
       b.kyc_decisions,
       b.kyc_cost,
       round(b.cac, 2) as cac,
       round(b.ad_only_cac, 2) as ad_only_cac,
       b.eligible_customers_12m,
       round(b.ltv_12m, 2) as ltv_12m,
       round(b.revenue_12m, 2) as revenue_12m,
       round(b.ltv_12m / b.cac, 3) as ltv_cac,
       round(b.revenue_12m / b.ad_only_cac, 3) as roas,
       pb.payback_month,
       case when b.cac is null then null when pb.payback_month is null then 0 else 1 end as paid_back_in_12m,
       round(b.credit_loss_per_customer, 2) as credit_loss_per_customer,
       round(b.ltv_12m - b.credit_loss_per_customer, 2) as risk_adj_ltv_12m,
       round((b.ltv_12m - b.credit_loss_per_customer) / b.cac, 3) as risk_adj_ltv_cac
from base b
outer apply (
    select min(cv.month_no) as payback_month
    from rpt.v_channel_curve cv
    where cv.acquisition_channel = b.acquisition_channel
      and b.cac is not null
      and cv.avg_cum_margin >= b.cac
) pb;
go

-- Checks
-- 1. 5 channels; funded customers add up to 5,928
select count(*) as channels, sum(funded_customers) as funded_total
from rpt.v_channel_scorecard;

-- 2. The scorecard
select *
from rpt.v_channel_scorecard
order by acquisition_channel;
go

--------------------------------------------------------------------------------
-- STEP 08 | rpt.v_credit_by_segment                                      (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per acquisition channel and customer segment: credit risk
--           by cell.
-- COLUMNS : acquisition_channel, segment, funded_customers, loans_total,
--           loan_penetration, seasoned_loans, delinquent_loans, default_loans,
--           early_default_loans, delinquency_rate, default_rate,
--           early_default_rate, credit_loss, low_sample
-- SOURCE  : rpt.v_funded_customers, clean.customers, rpt.v_loan_dpd
-- RULES   : - Rates use seasoned loans only. loan_penetration = loans (all) /
--             funded customers.
--           - low_sample = 1 when the cell has fewer than 50 seasoned loans. Do
--             not read those cells as findings.
--           - The segment 'unknown' (missing in the source) is its own row.
-- USED BY : Question 5 (early-default heatmap, delinquency and default table).

create or alter view rpt.v_credit_by_segment as
with cells as (
    select fc.acquisition_channel, cus.segment, count(*) as funded_customers
    from rpt.v_funded_customers fc
    inner join clean.customers cus on fc.customer_id = cus.customer_id
    group by fc.acquisition_channel, cus.segment
),
loan_cells as (
    select acquisition_channel,
           segment,
           count(*) as loans_total,
           sum(window_complete) as seasoned_loans,
           sum(is_delinquent_30) as delinquent_loans,
           sum(is_default_90) as default_loans,
           sum(is_early_default) as early_default_loans,
           sum(credit_loss) as credit_loss
    from rpt.v_loan_dpd
    group by acquisition_channel, segment
)
select c.acquisition_channel,
       c.segment,
       c.funded_customers,
       coalesce(l.loans_total, 0) as loans_total,
       round(1.0 * coalesce(l.loans_total, 0) / c.funded_customers, 4) as loan_penetration,
       coalesce(l.seasoned_loans, 0) as seasoned_loans,
       coalesce(l.delinquent_loans, 0) as delinquent_loans,
       coalesce(l.default_loans, 0) as default_loans,
       coalesce(l.early_default_loans, 0) as early_default_loans,
       round(1.0 * l.delinquent_loans / nullif(l.seasoned_loans, 0), 4) as delinquency_rate,
       round(1.0 * l.default_loans / nullif(l.seasoned_loans, 0), 4) as default_rate,
       round(1.0 * l.early_default_loans / nullif(l.seasoned_loans, 0), 4) as early_default_rate,
       coalesce(l.credit_loss, 0) as credit_loss,
       case when coalesce(l.seasoned_loans, 0) < 50 then 1 else 0 end as low_sample
from cells c
left join loan_cells l on c.acquisition_channel = l.acquisition_channel and c.segment = l.segment;
go

-- Checks
-- 1. Totals: 5,928 funded customers, 2,290 loans, 1,587 seasoned
select count(*) as cells,
       sum(funded_customers) as funded_total,
       sum(loans_total) as loans_total,
       sum(seasoned_loans) as seasoned_total,
       sum(low_sample) as low_sample_cells
from rpt.v_credit_by_segment;

-- 2. Early-default rate: channel by segment (NULL = no seasoned loans)
select acquisition_channel, segment, seasoned_loans, early_default_rate, low_sample
from rpt.v_credit_by_segment
order by acquisition_channel, segment;
go

--------------------------------------------------------------------------------
-- STEP 09 | rpt.v_campaign_cac                                           (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per campaign (25): spend, credited customers, cost per
--           credited customer and the waste flag.
-- COLUMNS : campaign_id, campaign_name, channel_name, objective, total_spend,
--           zero_impression_spend, zero_impression_share, credited_customers,
--           campaign_cac, channel_median_cac, cac_vs_median, is_wasteful,
--           spend_without_customers
-- SOURCE  : clean.campaigns, clean.channels, clean.daily_ad_spend,
--           rpt.v_touch_credit
-- RULES   : - credited_customers = position-based credit (40/40/20), the same
--             model as Question 3. campaign_cac = total spend / credited
--             customers.
--           - channel_median_cac = median campaign CAC inside the campaign's
--             channel. is_wasteful = 1 when campaign_cac is at least 2x that
--             median and total spend is at least EUR 2,000.
--           - Organic campaigns have no spend, so their CAC is NULL and they
--             are never flagged. Zero-impression spend stays in total_spend and
--             is shown separately.
-- USED BY : Question 4.

create or alter view rpt.v_campaign_cac as
with spend as (
    select campaign_id,
           sum(spend) as total_spend,
           sum(case when zero_impressions = 1 then spend else 0 end) as zero_impression_spend
    from clean.daily_ad_spend
    group by campaign_id
),
credit as (
    select campaign_id, sum(credit_position) as credited_customers
    from rpt.v_touch_credit
    where campaign_id is not null
    group by campaign_id
),
camp as (
    select cam.campaign_id,
           cam.campaign_name,
           ch.channel_name,
           cam.objective,
           coalesce(sp.total_spend, 0) as total_spend,
           coalesce(sp.zero_impression_spend, 0) as zero_impression_spend,
           coalesce(cr.credited_customers, 0) as credited_customers,
           case when sp.total_spend > 0 and cr.credited_customers > 0
                then sp.total_spend / cr.credited_customers end as campaign_cac
    from clean.campaigns cam
    inner join clean.channels ch on cam.channel_id = ch.channel_id
    left join spend sp on cam.campaign_id = sp.campaign_id
    left join credit cr on cam.campaign_id = cr.campaign_id
),
with_median as (
    select camp.*,
           percentile_cont(0.5) within group (order by campaign_cac) over (partition by channel_name) as channel_median_cac
    from camp
)
select campaign_id,
       campaign_name,
       channel_name,
       objective,
       round(total_spend, 2) as total_spend,
       round(zero_impression_spend, 2) as zero_impression_spend,
       round(zero_impression_spend / nullif(total_spend, 0), 4) as zero_impression_share,
       round(credited_customers, 2) as credited_customers,
       round(campaign_cac, 2) as campaign_cac,
       round(channel_median_cac, 2) as channel_median_cac,
       round(campaign_cac / nullif(channel_median_cac, 0), 2) as cac_vs_median,
       case when total_spend >= 2000 and campaign_cac >= 2 * channel_median_cac then 1 else 0 end as is_wasteful,
       case when total_spend > 0 and credited_customers = 0 then 1 else 0 end as spend_without_customers
from with_median;
go

-- Checks
-- 1. 25 campaigns; spend adds up to the daily_ad_spend total; credit adds up to the attributed customers
select count(*) as campaigns,
       round(sum(total_spend), 2) as spend_in_view,
       (select round(sum(spend), 2) from clean.daily_ad_spend) as spend_in_source,
       round(sum(credited_customers), 2) as credited_in_view,
       (select round(sum(credit_position), 2) from rpt.v_touch_credit where campaign_id is not null) as credited_in_source,
       sum(is_wasteful) as wasteful_campaigns
from rpt.v_campaign_cac;

-- 2. The campaigns, most expensive first
select campaign_name, channel_name, total_spend, credited_customers, campaign_cac, channel_median_cac, is_wasteful
from rpt.v_campaign_cac
order by campaign_cac desc;
go

--------------------------------------------------------------------------------
-- STEP 10 | rpt.v_budget_inputs                                          (VIEW)
--------------------------------------------------------------------------------
-- GRAIN   : One row per paid channel per month (4 channels x 24 months): the
--           inputs of the Excel budget model.
-- COLUMNS : channel_name, month_start, ad_spend, credited_customers,
--           in_baseline_quarter, risk_adj_ltv_12m, baseline_quarter_spend
-- SOURCE  : clean.daily_ad_spend, clean.campaigns, clean.channels,
--           rpt.v_touch_credit, rpt.v_funded_customers, rpt.v_channel_scorecard
-- RULES   : - Organic is not in the budget (no spend), so it has no rows.
--           - credited_customers = position-based credit for customers whose
--             first deposit fell in the month, credited to the channel of the
--             clicked campaign.
--           - in_baseline_quarter = 1 for July to September 2026 (the baseline
--             budget). risk_adj_ltv_12m comes from the scorecard.
-- USED BY : the headline question (Excel response curves and Solver).

create or alter view rpt.v_budget_inputs as
with months as (
    select distinct datefromparts(year(spend_date), month(spend_date), 1) as month_start
    from clean.daily_ad_spend
),
paid_channels as (
    select channel_name
    from clean.channels
    where has_spend = 1
),
monthly_spend as (
    select ch.channel_name,
           datefromparts(year(sp.spend_date), month(sp.spend_date), 1) as month_start,
           sum(sp.spend) as ad_spend
    from clean.daily_ad_spend sp
    inner join clean.campaigns cam on sp.campaign_id = cam.campaign_id
    inner join clean.channels ch on cam.channel_id = ch.channel_id
    group by ch.channel_name, datefromparts(year(sp.spend_date), month(sp.spend_date), 1)
),
monthly_credit as (
    select tc.touch_channel as channel_name,
           datefromparts(year(fc.first_deposit_date), month(fc.first_deposit_date), 1) as month_start,
           sum(tc.credit_position) as credited_customers
    from rpt.v_touch_credit tc
    inner join rpt.v_funded_customers fc on tc.customer_id = fc.customer_id
    group by tc.touch_channel,
             datefromparts(year(fc.first_deposit_date), month(fc.first_deposit_date), 1)
),
grid as (
    select pc.channel_name, m.month_start,
           coalesce(ms.ad_spend, 0) as ad_spend,
           coalesce(mc.credited_customers, 0) as credited_customers,
           case when m.month_start between '2026-07-01' and '2026-09-01' then 1 else 0 end as in_baseline_quarter
    from paid_channels pc
    cross join months m
    left join monthly_spend ms on pc.channel_name = ms.channel_name and m.month_start = ms.month_start
    left join monthly_credit mc on pc.channel_name = mc.channel_name and m.month_start = mc.month_start
)
select g.channel_name,
       g.month_start,
       round(g.ad_spend, 2) as ad_spend,
       round(g.credited_customers, 2) as credited_customers,
       g.in_baseline_quarter,
       sc.risk_adj_ltv_12m,
       round(sum(case when g.in_baseline_quarter = 1 then g.ad_spend else 0 end)
             over (partition by g.channel_name), 2) as baseline_quarter_spend
from grid g
left join rpt.v_channel_scorecard sc on g.channel_name = sc.acquisition_channel;
go

-- Checks
-- 1. 4 channels x 24 months = 96 rows; spend adds up to the source
select count(*) as total_rows,
       count(distinct channel_name) as channels,
       count(distinct month_start) as months,
       round(sum(ad_spend), 2) as spend_in_view,
       (select round(sum(spend), 2) from clean.daily_ad_spend) as spend_in_source
from rpt.v_budget_inputs;

-- 2. Baseline budget per channel (July to September 2026) and the 12-month value per customer
select channel_name,
       max(baseline_quarter_spend) as baseline_quarter_spend,
       max(risk_adj_ltv_12m) as risk_adj_ltv_12m,
       round(sum(credited_customers), 1) as credited_customers_24m
from rpt.v_budget_inputs
group by channel_name
order by channel_name;
go
