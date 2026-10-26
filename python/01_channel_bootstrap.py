"""Bootstrap confidence intervals for CAC and LTV by channel.

Reads the reporting views in SQL Server (database NeobankGrowth) and answers one question:
which of the differences between channels are larger than chance?

  - CAC: resample the 24 months of each paid channel (ad spend and funded customers
    of the same month stay together) and recalculate spend / customers.
  - LTV 12m and risk-adjusted LTV: resample the customers with a complete month 12
    and recalculate the mean.
  - Pairwise: the share of resamples in which channel A beats channel B.

Run from the repository root:  python python/01_channel_bootstrap.py
Writes the results to python/results/ (CSV) and python/figures/ (PNG).
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc

SERVER = r".\SQLEXPRESS"
DATABASE = "NeobankGrowth"
N_BOOT = 10_000
SEED = 42
CHANNELS = ["referral", "affiliate", "paid_search", "paid_social", "organic"]
PAID = ["referral", "affiliate", "paid_search", "paid_social"]

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)

# ---- data -----------------------------------------------------------------------------
# one row per customer with a complete month 12: cumulative margin and credit loss
customers = pd.read_sql(
    """
    with eligible as (
        select customer_id, acquisition_channel
        from rpt.v_customer_month_margin
        where month_no = 12 and month_complete = 1
    ),
    margin12 as (
        select customer_id, sum(margin) as ltv_12m
        from rpt.v_customer_month_margin
        where month_no <= 12
        group by customer_id
    ),
    loss as (
        select customer_id, sum(coalesce(credit_loss, 0)) as credit_loss
        from rpt.v_loan_dpd
        where window_complete = 1
        group by customer_id
    )
    select e.customer_id, e.acquisition_channel,
           m.ltv_12m, coalesce(l.credit_loss, 0) as credit_loss
    from eligible e
    join margin12 m on e.customer_id = m.customer_id
    left join loss l on e.customer_id = l.customer_id
    """,
    conn,
)
customers["risk_adj"] = customers["ltv_12m"] - customers["credit_loss"]

# ad spend and funded customers per paid channel and month (recorded channel)
months = pd.read_sql(
    """
    with funded as (
        select acquisition_channel as channel_name,
               datefromparts(year(first_deposit_date), month(first_deposit_date), 1) as month_start,
               count(*) as funded
        from rpt.v_funded_customers
        group by acquisition_channel,
                 datefromparts(year(first_deposit_date), month(first_deposit_date), 1)
    )
    select b.channel_name, b.month_start, b.ad_spend, coalesce(f.funded, 0) as funded
    from rpt.v_budget_inputs b
    left join funded f on b.channel_name = f.channel_name and b.month_start = f.month_start
    """,
    conn,
)
conn.close()

rng = np.random.default_rng(SEED)


def ci(values):
    return np.percentile(values, [2.5, 97.5])


# ---- LTV and risk-adjusted LTV: resample customers -------------------------------------
boot = {"ltv": {}, "risk": {}}
rows = []
for ch in CHANNELS:
    d = customers[customers["acquisition_channel"] == ch]
    ltv, risk = d["ltv_12m"].to_numpy(), d["risk_adj"].to_numpy()
    idx = rng.integers(0, len(d), size=(N_BOOT, len(d)))
    boot["ltv"][ch] = ltv[idx].mean(axis=1)
    boot["risk"][ch] = risk[idx].mean(axis=1)
    rows.append({
        "channel": ch, "customers_with_month_12": len(d),
        "ltv_12m": ltv.mean(), "ltv_low": ci(boot["ltv"][ch])[0], "ltv_high": ci(boot["ltv"][ch])[1],
        "risk_adj_ltv": risk.mean(), "risk_low": ci(boot["risk"][ch])[0], "risk_high": ci(boot["risk"][ch])[1],
    })
ltv_table = pd.DataFrame(rows)

# ---- CAC: resample months --------------------------------------------------------------
boot_cac, rows = {}, []
for ch in PAID:
    d = months[months["channel_name"] == ch]
    spend, funded = d["ad_spend"].to_numpy(), d["funded"].to_numpy()
    idx = rng.integers(0, len(d), size=(N_BOOT, len(d)))
    boot_cac[ch] = spend[idx].sum(axis=1) / funded[idx].sum(axis=1)
    rows.append({
        "channel": ch, "months": len(d),
        "ad_only_cac": spend.sum() / funded.sum(),
        "cac_low": ci(boot_cac[ch])[0], "cac_high": ci(boot_cac[ch])[1],
    })
cac_table = pd.DataFrame(rows)

# ---- pairwise comparisons --------------------------------------------------------------
pairs = [
    ("affiliate", "paid_search", "ltv", "affiliate has a higher LTV than paid search"),
    ("affiliate", "referral", "ltv", "affiliate has a higher LTV than referral"),
    ("referral", "organic", "risk", "referral has a higher risk-adjusted LTV than organic"),
    ("referral", "paid_search", "risk", "referral has a higher risk-adjusted LTV than paid search"),
    ("referral", "affiliate", "risk", "referral has a higher risk-adjusted LTV than affiliate"),
    ("paid_search", "affiliate", "risk", "paid search has a higher risk-adjusted LTV than affiliate"),
]
rows = []
for a, b, kind, text in pairs:
    diff = boot[kind][a] - boot[kind][b]
    rows.append({"claim": text, "mean_difference": diff.mean(),
                 "diff_low": ci(diff)[0], "diff_high": ci(diff)[1],
                 "share_of_resamples_true": (diff > 0).mean()})
for a, b in [("paid_social", "paid_search"), ("paid_social", "affiliate"), ("affiliate", "referral")]:
    diff = boot_cac[a] - boot_cac[b]
    rows.append({"claim": f"{a} has a higher CAC than {b}", "mean_difference": diff.mean(),
                 "diff_low": ci(diff)[0], "diff_high": ci(diff)[1],
                 "share_of_resamples_true": (diff > 0).mean()})
pair_table = pd.DataFrame(rows)

# ---- save ------------------------------------------------------------------------------
out = os.path.join(here, "results")
ltv_table.round(2).to_csv(os.path.join(out, "ltv_bootstrap.csv"), index=False)
cac_table.round(2).to_csv(os.path.join(out, "cac_bootstrap.csv"), index=False)
pair_table.round(3).to_csv(os.path.join(out, "pairwise_bootstrap.csv"), index=False)
pd.set_option("display.width", 200)
print(ltv_table.round(2).to_string(index=False), "\n")
print(cac_table.round(2).to_string(index=False), "\n")
print(pair_table.round(3).to_string(index=False))

# ---- figure ----------------------------------------------------------------------------
NAVY, ORANGE, GREY = "#1F3864", "#C55A11", "#7F7F7F"
fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))

t = cac_table.sort_values("ad_only_cac")
ax = axes[0]
ax.errorbar(t["ad_only_cac"], range(len(t)), xerr=[t["ad_only_cac"] - t["cac_low"], t["cac_high"] - t["ad_only_cac"]],
            fmt="o", color=NAVY, capsize=4)
ax.set_yticks(range(len(t)), t["channel"]); ax.set_title("Ad-only CAC (EUR), 95% interval", loc="left", fontsize=11)

t = ltv_table.sort_values("ltv_12m")
ax = axes[1]
ax.errorbar(t["ltv_12m"], range(len(t)), xerr=[t["ltv_12m"] - t["ltv_low"], t["ltv_high"] - t["ltv_12m"]],
            fmt="o", color=NAVY, capsize=4)
ax.set_yticks(range(len(t)), t["channel"]); ax.set_title("12-month LTV (EUR), 95% interval", loc="left", fontsize=11)

t = ltv_table.sort_values("risk_adj_ltv")
ax = axes[2]
ax.errorbar(t["risk_adj_ltv"], range(len(t)), xerr=[t["risk_adj_ltv"] - t["risk_low"], t["risk_high"] - t["risk_adj_ltv"]],
            fmt="o", color=ORANGE, capsize=4)
ax.axvline(0, color=GREY, lw=1, ls="--")
ax.set_yticks(range(len(t)), t["channel"]); ax.set_title("Risk-adjusted LTV (EUR), 95% interval", loc="left", fontsize=11)

for ax in axes:
    ax.grid(axis="x", alpha=0.3); ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "bootstrap_intervals.png"), dpi=150)
print("done")
