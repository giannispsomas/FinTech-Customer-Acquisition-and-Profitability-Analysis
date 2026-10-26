# LTV Scenarios

The recommended allocation in the Excel model uses one value per channel: the risk-adjusted LTV measured in the data. The bootstrap in [Statistical_Comparison.md](Statistical_Comparison.md) shows that these values are uncertain. This note tests whether the recommendation survives that uncertainty. The results are on the sheet `LTV_Scenarios` of [excel/budget_model.xlsx](../excel/budget_model.xlsx).

## Method

- The risk-adjusted LTV of each channel is moved to the **low end** or the **high end** of its 95% bootstrap interval. The shift is the interval end minus the point estimate (for example referral: -98.15 or +76.15 EUR per customer). The values are on the sheet `Assumptions`, rows 25 to 32.
- The shift is added to the risk-adjusted LTV on the sheet `Unit_Economics`, so it flows into the net value per customer that the optimizer uses. The default is 0, which gives the delivered base case.
- For each case, Solver was run again (GRG Nonlinear, three starting points, the best result kept), with the same limits as the base case: 50% to 150% of baseline spend per channel (referral 120%) and the baseline budget as a ceiling.

Five cases: the base case, **pessimistic** (every channel at its low end), **optimistic** (every channel at its high end), and two mixed cases about referral, because referral is the channel whose positive value is not proven.

## Results

| Case | affiliate | paid search | paid social | referral | Total spend | Customers won | Net profit | Uplift vs baseline |
|---|---|---|---|---|---|---|---|---|
| Base case | 1,558 | 2,687 | 9,515 | 1,298 | 15,058 | 470 | -56,843 | +40,720 |
| Pessimistic | 1,558 | 2,687 | 9,515 | 541 | 14,301 | 435 | -106,048 | +65,144 |
| Optimistic | 1,558 | 8,062 | 9,515 | 1,298 | 20,433 | 630 | -9,141 | +21,663 |
| Referral weak, others strong | 1,558 | 8,062 | 9,515 | 541 | 19,676 | 595 | -26,881 | +22,592 |
| Referral strong, others weak | 1,558 | 2,687 | 9,515 | 1,298 | 15,058 | 470 | -88,308 | +64,216 |

Spend is in EUR per quarter. The baseline spend is 28,603.

## What holds and what depends on the assumptions

**Holds in all five cases**
- Affiliate and paid social stay at their lower limit (50% of baseline), even when their value is at the high end of the interval. Cutting them does not depend on the point estimates.
- The reallocation improves the quarter against the baseline in every case (+21,663 to +65,144).
- Net profit stays negative in every case. Marketing allocation alone does not fix profitability.

**Depends on the assumptions**
- **Referral at the upper limit.** Referral is raised to 120% of baseline only when its value is at the point estimate or above. When its value is at the low end (the interval includes zero), the model cuts it to its lower limit (541).
- **Paid search.** It stays at the point estimate's spend (2,687) except when its value is at the high end, where the model raises it to its 150% limit (8,062).

So the safest part of the recommendation is the cut in affiliate and paid social. The move of money into referral, and any change in paid search, should be done in steps and checked against results.

## Limits

- A case with every channel at the same end of its interval is more extreme than a real outcome, because the channels do not all move together. The mixed cases are closer to realistic.
- The shift changes the value per customer only. It leaves the response curves (customers per euro) as they are.
- The data and the default behaviour are synthetic. The intervals describe sampling uncertainty in this dataset only.
