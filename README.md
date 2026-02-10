# Semiconductor Manufacturing Data Quality & Yield Analytics Platform

> An end-to-end data engineering & analytics project simulating semiconductor manufacturing operations, focusing on data quality, traceability, and yield-related metrics.
---

## 📋 Project Motivation

Semiconductor manufacturing generates high-volume, high-complexity operational data across equipment monitoring, wafer processing, and quality testing. This project simulates a **production-like data platform** focusing on:

- **Data Quality & Validation**: Rule-based checks ensuring manufacturing data integrity
- **Traceability**: End-to-end lineage from raw wafer to final test results
- **Analytics Readiness**: Curated datasets optimized for yield analysis and equipment monitoring

**The schema and metrics are inspired by real semiconductor manufacturing workflows**, designed to mirror the data engineering challenges faced in companies like Lam Research, Applied Materials, and TSMC.

---

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                        DATA SOURCES                              │
│  Equipment Logs | Wafer Batches | Test Results | Maintenance    │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                      RAW LAYER                                   │
│  - Timestamp-based partitioning                                  │
│  - Original format preservation                                  │
│  - Audit trail for compliance                                    │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    STAGING LAYER                                 │
│  - Schema standardization                                        │
│  - Type casting & validation                                     │
│  - Watermark-based incremental processing                        │
│  - Deduplication logic                                           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   DATA QUALITY CHECKS                            │
│  ✓ Referential integrity (wafer → batch → equipment)           │
│  ✓ Process sequence validation                                  │
│  ✓ Range checks on test metrics                                 │
│  ✓ Temporal consistency (no time travel)                        │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CURATED LAYER                                 │
│  Fact Tables:                                                    │
│    - fact_wafer_tests                                           │
│    - fact_equipment_events                                      │
│  Dimension Tables:                                               │
│    - dim_wafer_batch                                            │
│    - dim_equipment                                              │
│    - dim_process_step                                           │
└────────────────┬────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────────────────┐
│                   ANALYTICS & DASHBOARDS                         │
│  - Yield by equipment/batch/time                                │
│  - Equipment health monitoring                                   │
│  - Root cause traceability                                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🎯 Key Features

### 1. **Production-Grade Data Pipelines**
- **Incremental Processing**: Watermark-based loading to handle large-scale manufacturing data
- **Idempotent Design**: Pipelines can be re-run safely without data duplication
- **Late-Arriving Data Handling**: Graceful processing of delayed equipment logs

### 2. **Manufacturing-Specific Data Quality**
- **Traceability Validation**: Every wafer traces back to batch → equipment → maintenance history
- **Process Sequence Checks**: Manufacturing steps must follow correct order (lithography → etch → test)
- **Range Validation**: Test metrics (yield %, defect density) validated against realistic bounds
- **Temporal Consistency**: Equipment status changes and timestamps checked for logical sequence

### 3. **Analytics-Ready Data Model**
- **Star Schema Design**: Fact and dimension tables optimized for OLAP queries
- **Pre-Aggregated Metrics**: Common KPIs (daily yield, equipment uptime) materialized for performance
- **Comprehensive Lineage**: From raw sensor data to business metrics, fully traceable

---

## 📊 Simulated Data Sources

The project simulates four key data streams common in semiconductor fabs:

| Data Source | Description | Key Fields | Update Frequency |
|-------------|-------------|------------|------------------|
| **Equipment Log** | Sensor readings, status changes, parameter adjustments | equipment_id, timestamp, status, temperature, pressure | Real-time (simulated: 1/sec) |
| **Wafer Batch** | Lot assignments, process routing | batch_id, lot_number, recipe, start_time | Per batch (simulated: ~100/day) |
| **Test Results** | Electrical/functional test outcomes | wafer_id, test_type, pass_fail, defect_count, bin_code | Post-process (simulated: aligned with batch completion) |
| **Maintenance Events** | Preventive/corrective maintenance | equipment_id, event_type, duration, parts_replaced | As-needed (simulated: ~5/day) |

*Data generation scripts produce realistic patterns including:*
- Seasonal yield variations
- Equipment degradation over time
- Batch-to-batch correlation
- Realistic failure modes

---

## 🔧 Technical Stack

| Component | Technology | Purpose |
|-----------|-----------|---------|
| **Language** | Python 3.9+ | Pipeline orchestration, data generation |
| **Data Processing** | Pandas, NumPy | ETL transformations |
| **Data Storage** | CSV/Parquet files (scalable to database) | Simulated data warehouse layers |
| **Data Quality** | Custom rule engine (YAML-based) | Manufacturing-specific validations |
| **Testing** | pytest | Unit tests for pipeline logic |
| **Documentation** | Markdown | Architecture and use cases |

---

## 🚀 Quick Start

### Prerequisites
```bash
python >= 3.9
pip install -r requirements.txt
```

### Run Full Pipeline
```bash
# 1. Generate simulated manufacturing data
python pipelines/generate_data.py --days 30 --batch-size 100

# 2. Ingest to staging layer with incremental processing
python pipelines/ingest_raw.py

# 3. Run data quality checks
python dq/dq_checks.py --layer staging

# 4. Build curated analytics layer
python pipelines/build_curated.py

# 5. Generate DQ report
python dq/generate_report.py
```

### View Analytics Results
```bash
# Run sample yield analysis
python analytics/yield_metrics.py

# Trace a specific wafer
python analytics/batch_trace.py --wafer-id W12345
```

---

## 📈 Analytics Use Cases

### 1. **Yield Monitoring Dashboard**
**Business Question**: *What is our current yield performance by equipment and process step?*

```sql
-- See: analytics/yield_metrics.sql
SELECT 
    e.equipment_id,
    e.equipment_type,
    ps.process_step,
    COUNT(DISTINCT wt.wafer_id) as total_wafers,
    SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed_wafers,
    ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) as yield_pct
FROM fact_wafer_tests wt
JOIN dim_equipment e ON wt.equipment_id = e.equipment_id
JOIN dim_process_step ps ON wt.process_step_id = ps.process_step_id
WHERE wt.test_date >= CURRENT_DATE - INTERVAL '7 days'
GROUP BY e.equipment_id, e.equipment_type, ps.process_step
HAVING COUNT(*) >= 30  -- Statistical significance threshold
ORDER BY yield_pct DESC;
```

**Output Metrics**:
- Yield % by equipment (identifies underperforming tools)
- Yield trends over time (detects process drift)
- Pareto analysis of defect types

---

### 2. **Equipment Health Monitoring**
**Business Question**: *Which equipment requires preventive maintenance based on performance degradation?*

```sql
-- See: analytics/equipment_health.sql
WITH equipment_metrics AS (
    SELECT 
        equipment_id,
        DATE_TRUNC('day', event_timestamp) as date,
        AVG(CASE WHEN status = 'RUNNING' THEN 1 ELSE 0 END) as uptime_ratio,
        COUNT(CASE WHEN status = 'ALARM' THEN 1 END) as alarm_count
    FROM fact_equipment_events
    WHERE event_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY equipment_id, DATE_TRUNC('day', event_timestamp)
)
SELECT 
    equipment_id,
    AVG(uptime_ratio) as avg_uptime,
    SUM(alarm_count) as total_alarms,
    CASE 
        WHEN AVG(uptime_ratio) < 0.85 THEN 'CRITICAL'
        WHEN SUM(alarm_count) > 10 THEN 'WARNING'
        ELSE 'HEALTHY'
    END as health_status
FROM equipment_metrics
GROUP BY equipment_id
ORDER BY avg_uptime ASC;
```

**Output Metrics**:
- Equipment uptime %
- Mean time between failures (MTBF)
- Alarm frequency and root causes

---

### 3. **Root Cause Traceability**
**Business Question**: *For a failed wafer, what were the upstream factors (equipment, process parameters, batch conditions)?*

```sql
-- See: analytics/batch_trace.sql
-- Given wafer_id = 'W12345', trace back full history
WITH wafer_lineage AS (
    SELECT 
        wt.wafer_id,
        wt.batch_id,
        wb.lot_number,
        wb.recipe,
        wt.equipment_id,
        wt.process_step_id,
        wt.test_result,
        ee.status as equipment_status_during_process,
        me.event_type as recent_maintenance
    FROM fact_wafer_tests wt
    JOIN dim_wafer_batch wb ON wt.batch_id = wb.batch_id
    LEFT JOIN fact_equipment_events ee 
        ON wt.equipment_id = ee.equipment_id 
        AND ee.event_timestamp BETWEEN wt.start_time AND wt.end_time
    LEFT JOIN (
        SELECT equipment_id, event_type, event_timestamp,
               ROW_NUMBER() OVER (PARTITION BY equipment_id ORDER BY event_timestamp DESC) as rn
        FROM maintenance_events
    ) me ON wt.equipment_id = me.equipment_id AND me.rn = 1
    WHERE wt.wafer_id = 'W12345'
)
SELECT * FROM wafer_lineage
ORDER BY process_step_id;
```

**Traceability Chain**:
```
Failed Wafer W12345
  ↓
Batch B789 (Lot: LOT_2024_0156, Recipe: CMOS_28nm_v3)
  ↓
Equipment E042 (Status during process: RUNNING with 2 ALARMS)
  ↓
Recent Maintenance: Preventive (Chamber cleaning) on 2024-01-15
  ↓
Process Parameters: Temperature spike detected (+5°C above spec)
```

---

## 🛡️ Data Quality Strategy

### Manufacturing-Specific Validation Rules

The `dq/rules.yml` file defines 15+ validation rules critical for semiconductor data:

#### **Referential Integrity**
```yaml
- rule_id: DQ001
  name: Wafer-to-Batch Integrity
  description: Every wafer must have a valid batch_id
  severity: CRITICAL
  sql: |
    SELECT COUNT(*) as violations
    FROM staging.wafer_tests wt
    LEFT JOIN staging.wafer_batches wb ON wt.batch_id = wb.batch_id
    WHERE wb.batch_id IS NULL;
  threshold: 0
```

#### **Process Sequence Validation**
```yaml
- rule_id: DQ005
  name: Process Step Order
  description: Process steps must follow fab routing (lithography → etch → implant → test)
  severity: HIGH
  logic: |
    Steps with step_number N+1 cannot have timestamp earlier than step N for same batch
```

#### **Range Checks**
```yaml
- rule_id: DQ008
  name: Yield Bounds
  description: Batch yield must be between 0% and 100%
  severity: CRITICAL
  sql: |
    SELECT batch_id, yield_pct
    FROM staging.batch_summary
    WHERE yield_pct < 0 OR yield_pct > 100;
```

#### **Temporal Consistency**
```yaml
- rule_id: DQ012
  name: No Time Travel
  description: Equipment status changes cannot go backward in time
  severity: HIGH
  sql: |
    SELECT equipment_id, COUNT(*) as violations
    FROM (
      SELECT equipment_id, event_timestamp,
             LAG(event_timestamp) OVER (PARTITION BY equipment_id ORDER BY event_timestamp) as prev_time
      FROM staging.equipment_events
    ) sub
    WHERE event_timestamp < prev_time
    GROUP BY equipment_id;
```

### Data Quality Report Example

After running DQ checks, `dq_report.md` shows:

```
=== Data Quality Report ===
Run Date: 2024-02-09 14:32:15
Layer: staging

SUMMARY:
✅ Passed: 12 rules
⚠️  Warnings: 2 rules
❌ Failed: 1 rule

CRITICAL FAILURES:
[DQ008] Yield Bounds - FAILED
  - Found 3 batches with yield > 100%
  - Impact: Invalid business metrics, blocks curated layer build
  - Affected batches: B1234, B1256, B1290
  - Root cause: Data entry error in test_results.pass_count

WARNINGS:
[DQ010] Late Arriving Data - WARNING
  - 127 records arrived >24 hours after event_timestamp
  - Impact: Minor - reprocessing handled by watermark logic
  - Action: Monitor for systemic delays
```

---

## 📂 Project Structure

```
semicon-data-platform/
│
├── data/
│   ├── raw/                    # Simulated equipment/batch/test data (time-partitioned)
│   ├── stg/                    # Cleaned, typed, validated data
│   └── cur/                    # Analytics-ready fact/dimension tables
│
├── pipelines/
│   ├── generate_data.py        # Simulates realistic manufacturing data streams
│   ├── ingest_raw.py           # Incremental load with watermark tracking
│   ├── transform_stg.py        # Standardization and type casting
│   ├── build_curated.py        # Star schema construction
│   └── config.py               # Pipeline parameters (batch size, watermarks)
│
├── dq/
│   ├── rules.yml               # YAML-defined data quality rules
│   ├── dq_checks.py            # Rule execution engine
│   ├── generate_report.py      # Markdown/HTML report generation
│   └── dq_report.md            # Latest DQ results
│
├── analytics/
│   ├── yield_metrics.sql       # Yield calculations by equipment/batch/time
│   ├── equipment_health.sql    # Uptime, MTBF, alarm analysis
│   └── batch_trace.sql         # Wafer-to-batch-to-equipment lineage queries
│
├── tests/
│   ├── test_pipelines.py       # Unit tests for ETL logic
│   └── test_dq.py              # Data quality rule validation
│
├── docs/
│   ├── architecture.md         # Detailed architecture documentation
│   ├── data_model.md           # Schema definitions and ERD
│   └── lam_use_cases.md        # How this maps to real Lam workflows
│
├── requirements.txt            # Python dependencies
└── README.md                   # This file
```

---

## 🎓 Learning Outcomes & Skills Demonstrated

This project showcases production-ready data engineering skills relevant to semiconductor manufacturing:

### **Data Engineering**
- ✅ Incremental ETL with watermark-based change data capture
- ✅ Idempotent pipeline design for reliable re-runs
- ✅ Multi-layer data architecture (raw → staging → curated)
- ✅ Star schema modeling for analytics workloads

### **Data Quality & Governance**
- ✅ Rule-based validation framework
- ✅ Manufacturing-specific quality checks (traceability, sequence, range)
- ✅ Automated DQ reporting and alerting

### **Domain Knowledge**
- ✅ Semiconductor manufacturing workflow understanding
- ✅ Yield analysis and equipment monitoring metrics
- ✅ Root cause analysis through data lineage

### **Software Engineering**
- ✅ Modular, testable code structure
- ✅ Configuration management (YAML-based rules)
- ✅ Version control best practices
- ✅ Documentation for technical and non-technical audiences

---

## 🗺️ Roadmap & Future Enhancements

- [ ] **Database Integration**: Migrate from file-based to PostgreSQL/Snowflake
- [ ] **Orchestration**: Add Apache Airflow DAGs for scheduled pipeline runs
- [ ] **Real-Time Processing**: Kafka integration for streaming equipment logs
- [ ] **Advanced Analytics**: Statistical process control (SPC) charts, anomaly detection
- [ ] **API Layer**: REST API for dashboard integration
- [ ] **Cloud Deployment**: Containerize with Docker, deploy to AWS/GCP

---

## 🤝 How This Maps to Lam Research

At Lam Research, data engineers work on similar challenges:

| This Project | Lam Research Equivalent |
|--------------|-------------------------|
| Equipment log simulation | Real-time sensor data from etch/deposition tools |
| Yield analytics | Production yield optimization |
| Data quality rules | Compliance & audit requirements (ISO, FDA) |
| Traceability queries | Failure analysis and root cause investigation |
| Incremental pipelines | High-volume data ingestion (TB/day scale) |

**Key Alignment**:
- **Manufacturing focus**: Not generic e-commerce/social media data
- **Data quality emphasis**: Critical in regulated semiconductor industry
- **Engineering rigor**: Production-grade code, not notebook experiments
- **Business impact**: Metrics directly tied to fab performance (yield, uptime, cost)
