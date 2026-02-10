# Interview Preparation Guide: Technical Questions & Answers

This document prepares you for technical interviews at Lam Research, with questions tailored to this project.

---

## 🎯 Project Elevator Pitch (30 seconds)

**Question**: "Tell me about this semiconductor project on your GitHub."

**Answer**:
> "I built an end-to-end data engineering platform simulating semiconductor manufacturing operations. It focuses on three areas critical to companies like Lam: data quality validation, equipment health monitoring, and yield analytics. The architecture uses a three-layer approach - raw for audit compliance, staging for validation, and curated for analytics. I designed it to mirror real production systems rather than a typical student project, with incremental pipelines, manufacturing-specific data quality rules, and traceability queries that would be used in actual root cause investigations."

**Why this works**: 
- Shows domain knowledge (semiconductor context)
- Demonstrates production mindset (compliance, validation)
- Positions you as solving real business problems

---

## 📊 Data Architecture Questions

### Q1: "Walk me through your data architecture. Why three layers?"

**Answer**:
> "I use a medallion architecture with three layers:
> 
> **Raw Layer**: Preserves original data exactly as received from equipment. This is critical for audit compliance in regulated industries - if there's ever a question about what actually happened, we have the source of truth. Files are partitioned by timestamp for efficient querying.
> 
> **Staging Layer**: Applies schema standardization, type casting, and deduplication. This is where incremental processing happens using watermark-based logic. I also run data quality checks here before promoting to curated.
> 
> **Curated Layer**: Analytics-ready data in a star schema. Fact tables for wafer tests and equipment events, dimension tables for batches and equipment. Pre-aggregated metrics for performance.
> 
> The separation ensures we never lose raw data while making analytics fast."

**Deep Dive Follow-up**: "How do you handle schema evolution?"
> "In raw, I preserve everything as-is. In staging, I version my transformation logic - if a schema changes, I create a new transformation version while keeping the old one for historical reprocessing. The curated layer has a fixed schema, and I backfill when adding new metrics."

---

### Q2: "How does your incremental pipeline work?"

**Answer**:
> "I use watermark-based processing to track what's been loaded. For each data source, I maintain a high-water mark - the maximum timestamp successfully processed.
> 
> **Process**:
> 1. Read the current watermark from metadata (e.g., last processed timestamp = '2024-01-15 10:00:00')
> 2. Query source for records where event_timestamp > watermark
> 3. Process and load new data
> 4. Update watermark to max(event_timestamp) from this batch
> 
> **Key design decisions**:
> - Idempotent: If a job fails mid-run, rerunning won't create duplicates
> - Late-arriving data: I handle records that arrive out-of-order using event_timestamp vs. ingestion_timestamp
> - Lookback window: Process watermark - 24 hours to catch stragglers
> 
> This is standard for high-volume manufacturing data where you can't reprocess terabytes daily."

**Follow-up**: "What if the watermark gets corrupted?"
> "I maintain both current and previous watermark values. If corruption is detected (e.g., watermark jumps backward impossibly), I can rollback to previous and reprocess. For full disaster recovery, raw layer is immutable so we can rebuild staging and curated from scratch."

---

### Q3: "Why did you choose this data model for the curated layer?"

**Answer**:
> "I used a star schema because the primary use case is OLAP analytics - yield trending, equipment performance, root cause analysis. 
> 
> **Fact Tables**:
> - `fact_wafer_tests`: Grain is one row per wafer per process step. Contains pass/fail, defect metrics, timestamps.
> - `fact_equipment_events`: Grain is one equipment status change. Contains sensor readings.
> 
> **Dimension Tables**:
> - `dim_wafer_batches`: Batch metadata, lot numbers, recipes
> - `dim_equipment`: Equipment specs, manufacturers, install dates
> - `dim_process_steps`: Process routing definitions
> 
> This denormalized structure allows fast aggregations for dashboards (e.g., 'yield by equipment type this week') without complex joins. For a transactional system, I'd use 3NF, but for analytics, star schema wins."

**Follow-up**: "What about slowly changing dimensions?"
> "Equipment table would be Type 2 SCD in production - if a tool gets upgraded, I'd keep historical versions with effective dates. For this project, I simplified to current state only, but I'd add effective_start_date and effective_end_date columns plus a current_flag for production."

---

## 🛡️ Data Quality Questions

### Q4: "Walk me through your data quality framework."

**Answer**:
> "I built a YAML-based rule engine with 20 validation rules across five categories:
> 
> **1. Referential Integrity**: Every wafer must trace to a valid batch, every batch to valid equipment. Manufacturing requires complete lineage for compliance.
> 
> **2. Temporal Consistency**: Process steps can't go backward in time, equipment status changes must be chronological. These catch data pipeline bugs.
> 
> **3. Range Validation**: Yield must be 0-100%, sensor readings within realistic bounds. Catches sensor malfunctions or data entry errors.
> 
> **4. Completeness**: Required fields like wafer_id, equipment_id must be present. Missing keys break analytics.
> 
> **5. Manufacturing Logic**: Each batch should have 24-26 wafers (standard for 300mm lots), test durations should be 10 sec to 1 hour.
> 
> Each rule has a severity (CRITICAL/HIGH/MEDIUM/WARNING) and threshold. CRITICAL violations block the pipeline; warnings get logged for investigation."

**Follow-up**: "How do you handle false positives?"
> "Thresholds are key. For example, I allow up to 100 temperature readings outside range because sensors occasionally glitch. If violations exceed threshold, it indicates a systematic issue. I also trend DQ metrics - if a rule that usually passes 100% suddenly shows 50 violations, that's actionable even if threshold is 100."

---

### Q5: "What happens when a data quality check fails?"

**Answer**:
> "Depends on severity:
> 
> **CRITICAL failures** (e.g., broken referential integrity):
> 1. Pipeline stops - I don't promote bad data to curated
> 2. Generate detailed DQ report with examples of violations
> 3. Alert data engineering team (in production: Slack/PagerDuty)
> 4. Data stays in staging for investigation
> 
> **HIGH/MEDIUM failures**:
> 1. Pipeline continues but flags data
> 2. Add 'dq_warning' column to curated tables
> 3. Analysts can filter out flagged data or investigate
> 
> **WARNINGS**:
> 1. Log to DQ dashboard
> 2. No pipeline impact
> 3. Review in weekly data quality meetings
> 
> The key is: never let bad data silently propagate. In manufacturing, wrong yield numbers lead to bad business decisions."

---

## 🔍 Analytics & Business Impact Questions

### Q6: "How would you use this system to investigate a yield drop?"

**Answer**:
> "Let's say a fab reports batch B12345 had 75% yield instead of the usual 95%. Here's my investigation workflow:
> 
> **Step 1: Batch-level analysis** (`analytics/batch_trace.sql`)
> - Get complete batch history: lot number, recipe, equipment used
> - Identify which process step had the most failures
> - Check if this was an isolated batch or part of a trend
> 
> **Step 2: Equipment health check** (`analytics/equipment_health.sql`)
> - For each piece of equipment used in that batch, check:
>   - Were there alarms during processing?
>   - Has uptime been declining?
>   - Recent maintenance events?
> - Look for degradation signals (increasing temperature variability, alarm frequency)
> 
> **Step 3: Wafer-level trace** (`analytics/batch_trace.sql` - wafer trace query)
> - Pick a few failed wafers and trace their complete history
> - Check equipment conditions during each process step
> - Look for patterns (e.g., all failures on Tool #3, or after 5pm when pressure drifted)
> 
> **Step 4: Cross-batch correlation**
> - Check if batches before/after on same equipment also had issues
> - Look for contamination patterns
> 
> **Step 5: Root cause hypothesis**
> Based on findings, form hypotheses:
> - Equipment degradation → Schedule maintenance
> - Recipe issue → Investigate process parameters
> - Material problem → Check lot-level trends
> 
> All queries return results in seconds thanks to the curated layer design."

**Follow-up**: "What if you find nothing in the data?"
> "Then I'd question data quality itself. Maybe sensors malfunctioned and we're missing critical readings. Or the failure mode isn't captured by our current metrics. I'd work with process engineers to identify what data we need to collect, then enhance the pipeline."

---

### Q7: "What business metrics would you put on an executive dashboard?"

**Answer**:
> "I'd focus on KPIs that directly impact revenue and cost:
> 
> **Yield Metrics** (top priority):
> - Overall fab yield % (target: >95%)
> - Yield trend (7-day moving average) - alerts if dropping
> - Pareto of defect types (focus improvement on top 20%)
> - First-pass yield vs. final yield (measures rework cost)
> 
> **Equipment Health**:
> - Equipment uptime % by tool type
> - Mean time between failures (MTBF)
> - Tools requiring preventive maintenance (ranked by criticality score)
> 
> **Operational Efficiency**:
> - Batches processed today vs. target
> - Average cycle time per process step
> - Equipment utilization %
> 
> **Data Quality**:
> - % of batches passing all DQ checks
> - Critical DQ failures in last 24 hours
> 
> Each metric has a target range, and dashboard shows red/yellow/green status. Executives don't need SQL - they need actionable alerts."

---

## 💻 Technical Implementation Questions

### Q8: "How did you generate realistic test data?"

**Answer**:
> "I designed the data generator to simulate real manufacturing patterns, not just random numbers:
> 
> **Equipment aging**: Older tools have more variability in sensor readings and higher alarm rates. I model degradation as a factor that increases with tool age.
> 
> **Batch correlation**: Yield isn't independent - if one batch has issues, nearby batches often do too (e.g., chamber needs cleaning). I inject temporal correlation.
> 
> **Failure modes**: Realistic defect distributions (exponential for defect density), bin codes that match real test classifications.
> 
> **Seasonal patterns**: Yield varies slightly by day of week (weekend maintenance effects).
> 
> **Outliers**: Intentional anomalies for testing (batches with 0% yield, equipment temperature spikes) to validate DQ rules.
> 
> The goal was: if a Lam engineer saw this data, they'd recognize realistic patterns, not immediately spot it as fake."

---

### Q9: "How would you scale this to production volumes?"

**Answer**:
> "Current design handles ~100K records/day easily. For production scale (millions/day):
> 
> **Infrastructure**:
> - Replace CSV files with cloud data warehouse (Snowflake, Databricks)
> - Use Parquet with partitioning by date for fast queries
> - Migrate to Spark for parallel processing instead of Pandas
> 
> **Architecture changes**:
> - Add orchestration (Airflow) for scheduling and dependency management
> - Implement Delta Lake for ACID transactions on data lake
> - Cache frequently-accessed curated tables in Redis for sub-second dashboard queries
> 
> **Data Quality at scale**:
> - Run DQ checks in parallel using Spark
> - Sample-based validation for huge datasets (check 5% of records for expensive rules)
> - Incremental DQ - only validate new data, not full dataset
> 
> **Monitoring**:
> - Prometheus metrics for pipeline performance
> - Data observability platform (Monte Carlo, Great Expectations) for automatic anomaly detection
> 
> But the core logic - watermark processing, layered architecture, DQ rules - stays the same. Scaling is about infrastructure, not redesigning concepts."

---

### Q10: "What testing strategy would you implement?"

**Answer**:
> "I'd implement four test levels:
> 
> **1. Unit Tests** (pytest):
> - Test DQ rule logic in isolation
> - Mock data fixtures for edge cases
> - Test watermark update logic
> 
> **2. Integration Tests**:
> - Run full pipeline on small test dataset
> - Verify end-to-end: raw → staging → curated
> - Check DQ report generation
> 
> **3. Data Quality Tests**:
> - These ARE the tests - DQ rules validate production data
> - Treat DQ failures like test failures in CI/CD
> 
> **4. Regression Tests**:
> - Golden dataset approach: freeze known-good output
> - After code changes, verify results match golden set
> - Catch unexpected changes in calculated metrics
> 
> **CI/CD Pipeline**:
> ```
> git push → GitHub Actions → run tests → deploy to dev → manual review → promote to prod
> ```
> 
> In manufacturing, data quality IS testing. A bug that miscalculates yield by 1% could cost millions in bad decisions."

---

## 🏢 Behavioral & Situational Questions

### Q11: "Why are you interested in Lam Research specifically?"

**Answer**:
> "I'm drawn to Lam for three reasons:
> 
> **1. Domain**: Semiconductor manufacturing is technically fascinating and economically critical. The data challenges - high volume, real-time processing, traceability requirements - are exactly what I want to work on.
> 
> **2. Impact**: When a Lam tool goes down, a customer loses $100K+/hour. The data engineering work directly impacts fab uptime and yield - there's clear business value, not just abstract metrics.
> 
> **3. Technical growth**: Lam's scale (processing terabytes daily from global fabs) and complexity (streaming sensor data, predictive models) would push me to level up my skills in ways smaller companies can't offer.
> 
> I built this project specifically to prepare for this kind of role - manufacturing data isn't like e-commerce or social media, and I wanted to demonstrate I understand the unique requirements."

---

### Q12: "Tell me about a time you debugged a difficult data issue."

**Answer** (if you've worked with data before - adapt to your experience):
> "In [previous project/internship], we had a recurring issue where daily sales reports showed revenue spikes every Monday that weren't real.
> 
> **Investigation**:
> - First, I checked if it was a timezone issue - no, timestamps were correct
> - Then looked at the data pipeline - found we were using CURRENT_DATE instead of transaction_date for filtering
> - Every Monday, we'd re-process Sunday's data because CURRENT_DATE rolled over
> 
> **Root cause**: Poor handling of late-arriving data plus a non-idempotent pipeline
> 
> **Fix**: 
> 1. Switched to watermark-based incremental loading (like in this semiconductor project)
> 2. Made pipeline idempotent by upserting instead of inserting
> 3. Added data quality check: 'daily revenue can't exceed 2x moving average' to catch similar issues
> 
> **Lesson**: Always design for idempotency when dealing with production data pipelines."

---

## 🎓 Questions to Ask THEM

### Smart questions to ask your interviewer:

**Technical**:
- "What's your current data architecture for equipment logs? Are you on-prem or cloud?"
- "How do you handle schema evolution when equipment firmware updates change sensor outputs?"
- "What's the most challenging data quality issue you've encountered in manufacturing data?"

**Business**:
- "What's the typical customer engagement - do you provide analytics platforms, or is it just equipment sales?"
- "How does the data engineering team collaborate with process engineers on yield optimization?"

**Team/Culture**:
- "What does a typical sprint look like for the data team? How do you balance feature work vs. infrastructure?"
- "What's the on-call rotation like for production data pipelines?"

---

## 🚀 Red Flags to Avoid

**DON'T say**:
- ❌ "I just used pandas because it's what I know"
- ❌ "I didn't test it much"
- ❌ "The data is fake so accuracy doesn't matter"
- ❌ "I'd probably use [trendy tech] for everything"

**DO say**:
- ✅ "I chose this architecture because manufacturing data requires X"
- ✅ "I validated my approach by researching how real fabs handle this"
- ✅ "The simulation is realistic enough to demonstrate the concepts"
- ✅ "I'd evaluate [trendy tech] based on actual requirements"

---

## 📝 Final Tips

1. **Know your code**: Be ready to open the repo and explain ANY file
2. **Connect to business**: Every technical decision should tie to a business outcome
3. **Show curiosity**: Ask about their real problems, don't just talk about your project
4. **Be honest**: If you don't know something, say "I haven't worked with that, but here's how I'd approach learning it"

**Most important**: This project shows you think like a production engineer, not a student. That's what will get you hired.

---

*Good luck! 🚀*
