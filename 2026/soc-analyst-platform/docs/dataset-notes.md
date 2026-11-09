# Dataset Notes

Written during Week 1 setup (Razzaq). This documents what's already been downloaded, validated,
and fixed — so the ML/Triage work in Week 3 can start straight from clean data instead of
rediscovering these issues from scratch.

## Dataset choice

- **Primary (training): CICIDS2017** — larger, more widely used in this research area, and its
  benign/attack imbalance closely mirrors a real SOC's alert volume.
- **Cross-validation: UNSW-NB15** — captured in a different environment with a different feature
  distribution, which makes it a genuinely useful generalization test. If the classifier trained
  on CICIDS2017 still performs well on UNSW-NB15, that's a much stronger result for the report
  than testing on a held-out slice of the same dataset.

## Where the data lives

Raw datasets are **not committed to Git** (too large, and `ml/data/` is in `.gitignore`).
Everyone needs to download and place them locally in this exact structure:

```
ml/
  data/
    cicids2017/
      MachineLearningCVE/
        Monday-WorkingHours.pcap_ISCX.csv
        Tuesday-WorkingHours.pcap_ISCX.csv
        Wednesday-workingHours.pcap_ISCX.csv
        Thursday-WorkingHours-Morning-WebAttacks.pcap_ISCX.csv
        Thursday-WorkingHours-Afternoon-Infilteration.pcap_ISCX.csv
        Friday-WorkingHours-Morning.pcap_ISCX.csv
        Friday-WorkingHours-Afternoon-PortScan.pcap_ISCX.csv
        Friday-WorkingHours-Afternoon-DDos.pcap_ISCX.csv
    unsw_nb15/
      UNSW_NB15_training-set.csv
      UNSW_NB15_testing-set.csv
```

**Download links:**
- CICIDS2017 → `cicresearch.ca` → Browse dataset → CIC-IDS-2017 → CSVs → download
  `MachineLearningCSV.zip` (not `GeneratedLabelledFlows.zip` — that's an earlier processing
  stage with more redundant fields)
- UNSW-NB15 → official UNSW OneDrive share → `CSV Files` folder → download the pre-built
  `UNSW_NB15_training-set.csv` and `UNSW_NB15_testing-set.csv` (skip the 4 raw split files
  and the Argus/BRO/pcap folders — not needed)

Both require a short academic-use form (name, institution, email) — use your real college
email, some providers email the actual download link rather than showing it directly.

## Known issue: CICIDS2017 column names have leading spaces

Almost every column in the raw CSVs has a leading space, e.g. `' Label'` instead of `'Label'`,
`' Flow Duration'` instead of `'Flow Duration'`. This will cause a `KeyError` if you reference
columns by name without fixing it first.

**Fix — always run this immediately after loading:**
```python
df.columns = df.columns.str.strip()
```

## Per-day breakdown (CICIDS2017)

| File | Rows (approx.) | Label(s) present |
|---|---|---|
| Monday-WorkingHours.pcap_ISCX.csv | 529,918 | **BENIGN only** — normal traffic baseline day, no attacks |
| Tuesday-WorkingHours.pcap_ISCX.csv | ~445,000 | BENIGN + Brute Force (FTP/SSH) |
| Wednesday-workingHours.pcap_ISCX.csv | ~692,000 | BENIGN + DoS attacks, Heartbleed |
| Thursday-...-WebAttacks.pcap_ISCX.csv | ~170,000 | BENIGN + Web Attacks (Brute Force, XSS, SQL Injection) |
| Thursday-...-Infilteration.pcap_ISCX.csv | ~288,000 | BENIGN + Infiltration |
| Friday-WorkingHours-Morning.pcap_ISCX.csv | ~191,000 | BENIGN + Botnet |
| Friday-...-PortScan.pcap_ISCX.csv | ~286,000 | BENIGN + PortScan |
| Friday-...-DDos.pcap_ISCX.csv | ~225,000 | BENIGN + DDoS |

Row counts beyond Monday are approximate (from public documentation) — confirm exact counts
once you load each file, since minor version/mirror differences exist.

**Important for training:** Monday alone won't teach the classifier anything about attacks —
Ghouse will need to load and combine Tuesday through Friday (or all 8 files) to get a proper
mix of benign and attack traffic for training.

## Validated so far (Week 1)

- [x] CICIDS2017 downloaded, extracted, and loads correctly with pandas
- [x] Column names confirmed to have leading spaces; `.str.strip()` fix confirmed working
- [x] Monday file confirmed as 529,918 rows, 100% BENIGN (expected, not a bug)
- [x] UNSW-NB15 training/testing CSVs downloaded
- [ ] UNSW-NB15 not yet loaded/validated with pandas — do this before Week 3 if possible
- [ ] Combined multi-day CICIDS2017 loading not yet tested — Ghouse's first task in Week 3

## Quick-start snippet for Week 3

```python
import pandas as pd
import glob

# Load and combine all CICIDS2017 days
path = "ml/data/cicids2017/MachineLearningCVE/"
all_files = glob.glob(path + "*.csv")

df_list = []
for f in all_files:
    temp = pd.read_csv(f)
    temp.columns = temp.columns.str.strip()  # fix the whitespace issue
    df_list.append(temp)

df = pd.concat(df_list, ignore_index=True)
print(df.shape)
print(df['Label'].value_counts())
```