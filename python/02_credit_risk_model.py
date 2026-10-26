"""Credit risk model: why does affiliate default more?

Logistic regression on the seasoned loans (issued on or before 2026-03-31) with a 90+ days
past due default as the target. Two models are compared with repeated cross-validation:

  A: loan and borrower features only (grade, principal, term, segment)
  B: A plus the acquisition channel

If B is no better than A, the channel adds nothing once the loan mix is known, and the
affiliate result is explained by who borrows, not by the channel itself.

Run from the repository root:  python python/02_credit_risk_model.py
Writes results to python/results/ (CSV) and python/figures/ (PNG).
"""
import os

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
import pyodbc
from sklearn.compose import ColumnTransformer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score, roc_curve
from sklearn.model_selection import RepeatedStratifiedKFold, StratifiedKFold, cross_val_predict, cross_val_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import OneHotEncoder, StandardScaler

SERVER = r".\SQLEXPRESS"
DATABASE = "NeobankGrowth"
SEED = 42

here = os.path.dirname(os.path.abspath(__file__))
os.makedirs(os.path.join(here, "results"), exist_ok=True)
os.makedirs(os.path.join(here, "figures"), exist_ok=True)

conn = pyodbc.connect(
    f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={SERVER};DATABASE={DATABASE};"
    "Trusted_Connection=yes;TrustServerCertificate=yes;"
)
loans = pd.read_sql(
    """
    select loan_id, acquisition_channel, segment, grade, principal, term_months, apr,
           is_default_90 as default_90
    from rpt.v_loan_dpd
    where window_complete = 1
    """,
    conn,
)
conn.close()
loans["log_principal"] = np.log(loans["principal"])
y = loans["default_90"].to_numpy()
print(f"{len(loans)} seasoned loans, default rate {y.mean():.3f}")

LOAN_CAT = ["grade", "segment"]
LOAN_NUM = ["log_principal", "term_months"]


def make_model(with_channel):
    cat = LOAN_CAT + (["acquisition_channel"] if with_channel else [])
    pre = ColumnTransformer([
        ("cat", OneHotEncoder(handle_unknown="ignore"), cat),
        ("num", StandardScaler(), LOAN_NUM),
    ])
    return Pipeline([("prep", pre), ("lr", LogisticRegression(max_iter=2000))])


FEATURES = LOAN_CAT + LOAN_NUM + ["acquisition_channel"]
models = {"A: loan features only": make_model(False), "B: loan features + channel": make_model(True)}

# ---- repeated cross-validated ROC-AUC ----------------------------------------------------
cv = RepeatedStratifiedKFold(n_splits=5, n_repeats=10, random_state=SEED)
rows = []
for name, model in models.items():
    scores = cross_val_score(model, loans[FEATURES], y, cv=cv, scoring="roc_auc")
    rows.append({"model": name, "auc_mean": scores.mean(), "auc_sd": scores.std(),
                 "auc_low": np.percentile(scores, 2.5), "auc_high": np.percentile(scores, 97.5)})
auc_table = pd.DataFrame(rows)

# ---- out-of-fold predictions -------------------------------------------------------------
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=SEED)
oof = {name: cross_val_predict(m, loans[FEATURES], y, cv=skf, method="predict_proba")[:, 1]
       for name, m in models.items()}
loans["p_a"] = oof["A: loan features only"]
loans["p_b"] = oof["B: loan features + channel"]

# actual against predicted default rate by channel (model A does not know the channel)
by_channel = (loans.groupby("acquisition_channel")
              .agg(loans=("default_90", "size"), actual=("default_90", "mean"),
                   predicted_without_channel=("p_a", "mean"), predicted_with_channel=("p_b", "mean"))
              .reset_index())
by_channel["gap_actual_minus_predicted"] = by_channel["actual"] - by_channel["predicted_without_channel"]

# risk separation: out-of-fold predicted-risk quintiles (model B)
loans["risk_quintile"] = pd.qcut(loans["p_b"], 5, labels=["1 lowest", "2", "3", "4", "5 highest"])
quint = (loans.groupby("risk_quintile", observed=True)
         .agg(loans=("default_90", "size"), predicted=("p_b", "mean"), actual=("default_90", "mean"))
         .reset_index())

# share of each channel's loans in the highest-risk quintile
mix = (loans.assign(top=(loans["risk_quintile"] == "5 highest").astype(int))
       .groupby("acquisition_channel")["top"].mean().rename("share_in_highest_risk_quintile").reset_index())
by_channel = by_channel.merge(mix, on="acquisition_channel")

# is the gap between actual and predicted (model A) larger than chance? bootstrap the loans
rng = np.random.default_rng(SEED)
gap_rows = []
for ch, d in loans.groupby("acquisition_channel"):
    actual, pred = d["default_90"].to_numpy(), d["p_a"].to_numpy()
    idx = rng.integers(0, len(d), size=(10_000, len(d)))
    gap = actual[idx].mean(axis=1) - pred[idx].mean(axis=1)
    gap_rows.append({"acquisition_channel": ch, "gap_low": np.percentile(gap, 2.5), "gap_high": np.percentile(gap, 97.5)})
by_channel = by_channel.merge(pd.DataFrame(gap_rows), on="acquisition_channel")

# ---- coefficients of the full-sample model B ---------------------------------------------
final = make_model(True).fit(loans[FEATURES], y)
names = final.named_steps["prep"].get_feature_names_out()
coef = pd.DataFrame({"feature": names, "coefficient": final.named_steps["lr"].coef_[0]})
coef["odds_ratio"] = np.exp(coef["coefficient"])
coef = coef.sort_values("coefficient", ascending=False)

# ---- save and print ----------------------------------------------------------------------
out = os.path.join(here, "results")
auc_table.round(3).to_csv(os.path.join(out, "credit_model_auc.csv"), index=False)
by_channel.round(3).to_csv(os.path.join(out, "credit_model_by_channel.csv"), index=False)
quint.round(3).to_csv(os.path.join(out, "credit_model_risk_quintiles.csv"), index=False)
coef.round(3).to_csv(os.path.join(out, "credit_model_coefficients.csv"), index=False)
pd.set_option("display.width", 200)
print(auc_table.round(3).to_string(index=False), "\n")
print(by_channel.round(3).to_string(index=False), "\n")
print(quint.round(3).to_string(index=False), "\n")
print(coef.round(3).to_string(index=False))

# ---- figure ------------------------------------------------------------------------------
NAVY, ORANGE, GREY = "#1F3864", "#C55A11", "#7F7F7F"
fig, axes = plt.subplots(1, 3, figsize=(15, 4.6))

ax = axes[0]
for name, colour in zip(models, (GREY, NAVY)):
    fpr, tpr, _ = roc_curve(y, oof[name])
    ax.plot(fpr, tpr, color=colour, lw=2, label=f"{name} (AUC {roc_auc_score(y, oof[name]):.2f})")
ax.plot([0, 1], [0, 1], color="#BBBBBB", ls="--", lw=1)
ax.set_xlabel("False positive rate"); ax.set_ylabel("True positive rate")
ax.set_title("ROC curve, out-of-fold predictions", loc="left", fontsize=11); ax.legend(loc="lower right", fontsize=8)

ax = axes[1]
t = by_channel.sort_values("actual")
pos = np.arange(len(t))
ax.barh(pos + 0.2, t["actual"] * 100, height=0.38, color=ORANGE, label="Actual")
ax.barh(pos - 0.2, t["predicted_without_channel"] * 100, height=0.38, color=NAVY, label="Predicted from loan features only")
ax.set_yticks(pos, t["acquisition_channel"]); ax.set_xlabel("Default rate (%)")
ax.set_title("Default rate by channel: actual vs predicted", loc="left", fontsize=11); ax.legend(fontsize=8)

ax = axes[2]
ax.plot(quint["predicted"] * 100, quint["actual"] * 100, "o-", color=NAVY, lw=2)
top = max(quint["predicted"].max(), quint["actual"].max()) * 100
ax.plot([0, top], [0, top], color="#BBBBBB", ls="--", lw=1)
ax.set_xlabel("Predicted default rate (%)"); ax.set_ylabel("Actual default rate (%)")
ax.set_title("Risk quintiles: predicted vs actual", loc="left", fontsize=11)

for ax in axes:
    ax.grid(alpha=0.3); ax.spines[["top", "right"]].set_visible(False)
fig.tight_layout()
fig.savefig(os.path.join(here, "figures", "credit_risk_model.png"), dpi=150)
print("done")
