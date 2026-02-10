# Quick Start Guide

Get the semiconductor manufacturing data platform running in 5 minutes.

---

## ⚡ Quick Setup

### Prerequisites
```bash
# Requires Python 3.9+
python --version

# Clone or download this repository
cd semicon-data-platform
```

### Install Dependencies
```bash
pip install -r requirements.txt
```

---

## 🚀 Run the Full Pipeline

### Step 1: Generate Simulated Data
```bash
python pipelines/generate_data.py --days 30
```

**Output**:
```
✓ Generated 50 equipment records
✓ Generated 6 process steps
✓ Generated 142,560 equipment log records
✓ Generated 600 wafer batches
✓ Generated 90,000 test records
✓ Generated 245 maintenance events
```

Data will be in `data/raw/` directory.

---

### Step 2: Run Data Quality Checks
```bash
python dq/dq_checks.py --layer raw --report
```

**Output**:
```
Running Data Quality Checks - Layer: raw
✅ [DQ001] Wafer-to-Batch Integrity... PASS
✅ [DQ002] Batch-to-Equipment Integrity... PASS
⚠️  [DQ009] Equipment Temperature Range... WARNING (87 violations)
✅ [DQ012] Equipment ID Not Null... PASS

Data Quality Summary
✅ Passed:   17
⚠️  Warnings: 2
❌ Failed:   0
```

Report saved to `dq/dq_report.md`.

---

### Step 3: View Analytics (Manual)

Open `analytics/yield_metrics.sql` in your SQL editor or convert to pandas:

**Example**: Get equipment yield rankings
```python
import pandas as pd

# Load test results
tests = pd.read_csv('data/raw/test_results.csv')
equipment = pd.read_csv('data/raw/equipment_master.csv')

# Calculate yield by equipment
merged = tests.merge(equipment, on='equipment_id')
yield_by_eq = merged.groupby(['equipment_id', 'equipment_type']).agg({
    'wafer_id': 'count',
    'pass_fail': lambda x: (x == 'PASS').sum() / len(x) * 100
}).reset_index()
yield_by_eq.columns = ['equipment_id', 'equipment_type', 'wafer_count', 'yield_pct']

print(yield_by_eq.sort_values('yield_pct'))
```

---

## 📂 Project Structure

After running the pipeline, your directory should look like:

```
semicon-data-platform/
├── data/
│   └── raw/
│       ├── equipment_master.csv      (50 rows)
│       ├── process_steps.csv         (6 rows)
│       ├── equipment_logs.csv        (142K rows)
│       ├── wafer_batches.csv         (600 rows)
│       ├── test_results.csv          (90K rows)
│       └── maintenance_events.csv    (245 rows)
├── dq/
│   ├── rules.yml                     (20 validation rules)
│   ├── dq_checks.py                  (validation engine)
│   └── dq_report.md                  (latest results)
├── analytics/
│   ├── yield_metrics.sql             (7 queries)
│   ├── equipment_health.sql          (6 queries)
│   └── batch_trace.sql               (7 queries)
└── docs/
    ├── lam_use_cases.md              (business context)
    └── interview_prep.md             (Q&A guide)
```

---

## 🎯 What to Show Recruiters

### 1. **Show the README**
Open `README.md` - professional presentation with architecture diagram.

### 2. **Run Data Generation Live**
```bash
python pipelines/generate_data.py --days 7
```
Shows you can write production-like code.

### 3. **Show Data Quality Framework**
Open `dq/rules.yml` - demonstrates manufacturing domain knowledge.

### 4. **Explain an Analytics Query**
Open `analytics/batch_trace.sql` and walk through the "Complete Wafer Trace" query:
> "This query shows how we'd investigate a failed wafer - trace back through every process step, equipment used, and conditions during processing."

### 5. **Show Business Context**
Open `docs/lam_use_cases.md` - proves you understand how this maps to real work.

---

## 📊 Sample Analytics Outputs

### Yield by Equipment Type
```
equipment_type  | yield_pct | wafer_count
----------------|-----------|-------------
ETCH            | 94.2%     | 15,000
LITHO           | 93.8%     | 15,000
CVD             | 92.5%     | 15,000
TEST            | 95.7%     | 15,000
```

### Equipment Health Status
```
equipment_id | uptime_pct | alarms_30d | health_status
-------------|------------|------------|---------------
ETC001       | 96.2%      | 12         | 🟢 EXCELLENT
LIT003       | 87.4%      | 48         | 🟠 ACCEPTABLE
CVD002       | 82.1%      | 105        | 🔴 NEEDS ATTENTION
```

---

## 🛠️ Customization Options

### Generate More/Less Data
```bash
# Quick test (7 days)
python pipelines/generate_data.py --days 7

# Medium dataset (30 days) - recommended
python pipelines/generate_data.py --days 30

# Large dataset (90 days) - for performance testing
python pipelines/generate_data.py --days 90
```

### Adjust Equipment Count
Edit `pipelines/generate_data.py`, line 22:
```python
num_tools = np.random.randint(3, 8)  # Change to (5, 15) for more tools
```

### Modify Yield Distribution
Edit `pipelines/generate_data.py`, line 138:
```python
batch_yield_factor = np.random.normal(0.95, 0.05)  # Mean 95%, stddev 5%
```

---

## 📧 Interview Preparation

Before your interview, review:

1. **`docs/interview_prep.md`** - 12 common technical questions with answers
2. **`docs/lam_use_cases.md`** - How this maps to Lam Research workflows
3. **`README.md`** - Overall project narrative

**Pro tip**: Open all three files in browser tabs before interview for quick reference.

---

## 🐛 Troubleshooting

### "Module not found: pandas"
```bash
pip install -r requirements.txt
```

### "No data in raw layer"
Make sure you ran:
```bash
python pipelines/generate_data.py --days 30
```

### "Permission denied"
```bash
chmod +x pipelines/*.py
```

---

## 🚀 Next Steps

Once you've run the basic pipeline:

1. **Explore Analytics**: Open SQL files in `analytics/` and understand each query
2. **Customize DQ Rules**: Add your own validation rule to `dq/rules.yml`
3. **Extend Data Model**: Add a new dimension (e.g., `dim_operators` for technicians)
4. **Practice Interview Questions**: Go through `docs/interview_prep.md`

---

## 💡 Demo Script for Screenshare

**2-minute walkthrough for recruiters**:

1. **Open README** - scroll through architecture diagram
2. **Show file structure** in IDE - point out clean organization
3. **Run data generation**:
   ```bash
   python pipelines/generate_data.py --days 7
   ```
4. **Show output CSVs** - open `data/raw/test_results.csv` in Excel/spreadsheet
5. **Open `analytics/yield_metrics.sql`** - explain one query
6. **Show DQ rules** - open `dq/rules.yml`, highlight manufacturing-specific validations

**Total time**: 2 minutes. Shows professionalism and preparedness.

---

Good luck! 🎯
