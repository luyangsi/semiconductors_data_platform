-- Batch Traceability & Root Cause Analysis Queries
-- End-to-end lineage for semiconductor manufacturing

-- ============================================================================
-- 1. COMPLETE WAFER TRACE
-- ============================================================================
-- Purpose: Given a wafer ID, trace complete manufacturing history
-- Use Case: Failure investigation, audit compliance

-- Example usage: Replace 'W12345' with actual wafer_id
WITH wafer_history AS (
    SELECT 
        wt.wafer_id,
        wt.batch_id,
        wb.lot_number,
        wb.recipe,
        wb.start_time as batch_start,
        wb.end_time as batch_end,
        ps.process_step_id,
        ps.process_step_name,
        ps.equipment_type,
        wt.equipment_id,
        e.manufacturer,
        wt.start_time as step_start,
        wt.end_time as step_end,
        wt.pass_fail,
        wt.defect_density,
        wt.bin_code,
        -- Equipment conditions during processing
        (SELECT AVG(temperature_c)
         FROM fact_equipment_events ee
         WHERE ee.equipment_id = wt.equipment_id
           AND ee.event_timestamp BETWEEN wt.start_time AND wt.end_time) as avg_temp_during_process,
        (SELECT AVG(pressure_torr)
         FROM fact_equipment_events ee
         WHERE ee.equipment_id = wt.equipment_id
           AND ee.event_timestamp BETWEEN wt.start_time AND wt.end_time) as avg_pressure_during_process,
        (SELECT COUNT(*)
         FROM fact_equipment_events ee
         WHERE ee.equipment_id = wt.equipment_id
           AND ee.status = 'ALARM'
           AND ee.event_timestamp BETWEEN wt.start_time AND wt.end_time) as alarms_during_process
    FROM fact_wafer_tests wt
    JOIN dim_wafer_batches wb ON wt.batch_id = wb.batch_id
    JOIN dim_process_steps ps ON wt.process_step_id = ps.process_step_id
    JOIN dim_equipment e ON wt.equipment_id = e.equipment_id
    WHERE wt.wafer_id = 'B000001_W01'  -- << REPLACE WITH TARGET WAFER_ID
)
SELECT 
    wafer_id,
    batch_id,
    lot_number,
    recipe,
    batch_start,
    batch_end,
    process_step_id,
    process_step_name,
    equipment_type,
    equipment_id,
    manufacturer,
    step_start,
    step_end,
    TIMESTAMPDIFF(MINUTE, step_start, step_end) as duration_minutes,
    pass_fail,
    defect_density,
    bin_code,
    ROUND(avg_temp_during_process, 2) as avg_temp_c,
    ROUND(avg_pressure_during_process, 3) as avg_pressure_torr,
    alarms_during_process,
    CASE 
        WHEN pass_fail = 'FAIL' THEN '❌ FAILED HERE'
        ELSE '✓'
    END as status_indicator
FROM wafer_history
ORDER BY process_step_id;

-- ============================================================================
-- 2. BATCH-LEVEL ROOT CAUSE ANALYSIS
-- ============================================================================
-- Purpose: For low-yield batches, identify potential root causes
-- Use Case: Quality investigation

-- Example: Find root causes for batches with <85% yield
WITH low_yield_batches AS (
    SELECT 
        batch_id,
        COUNT(DISTINCT wafer_id) as wafer_count,
        SUM(CASE WHEN pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed,
        ROUND(100.0 * SUM(CASE WHEN pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT wafer_id), 2) as yield_pct
    FROM fact_wafer_tests
    GROUP BY batch_id
    HAVING yield_pct < 85
),
batch_factors AS (
    SELECT 
        lyb.batch_id,
        lyb.yield_pct,
        wb.lot_number,
        wb.recipe,
        wb.start_time,
        -- Equipment issues during batch
        (SELECT COUNT(DISTINCT ee.equipment_id)
         FROM fact_equipment_events ee
         JOIN fact_wafer_tests wt2 ON ee.equipment_id = wt2.equipment_id
         WHERE wt2.batch_id = lyb.batch_id
           AND ee.status = 'ALARM'
           AND ee.event_timestamp BETWEEN wb.start_time AND wb.end_time) as equipment_with_alarms,
        -- Recent maintenance
        (SELECT COUNT(*)
         FROM maintenance_events me
         JOIN fact_wafer_tests wt2 ON me.equipment_id = wt2.equipment_id
         WHERE wt2.batch_id = lyb.batch_id
           AND me.event_timestamp BETWEEN wb.start_time - INTERVAL '24 hours' AND wb.start_time) as recent_maintenance_count,
        -- Which step failed most
        (SELECT ps.process_step_name
         FROM fact_wafer_tests wt2
         JOIN dim_process_steps ps ON wt2.process_step_id = ps.process_step_id
         WHERE wt2.batch_id = lyb.batch_id
           AND wt2.pass_fail = 'FAIL'
         GROUP BY ps.process_step_name
         ORDER BY COUNT(*) DESC
         LIMIT 1) as most_failed_step,
        (SELECT COUNT(*)
         FROM fact_wafer_tests wt2
         WHERE wt2.batch_id = lyb.batch_id
           AND wt2.pass_fail = 'FAIL'
         GROUP BY wt2.process_step_id
         ORDER BY COUNT(*) DESC
         LIMIT 1) as failures_at_worst_step
    FROM low_yield_batches lyb
    JOIN dim_wafer_batches wb ON lyb.batch_id = wb.batch_id
)
SELECT 
    batch_id,
    lot_number,
    recipe,
    start_time,
    yield_pct,
    equipment_with_alarms,
    recent_maintenance_count,
    most_failed_step,
    failures_at_worst_step,
    CASE 
        WHEN equipment_with_alarms >= 3 THEN '🔴 Multiple equipment issues'
        WHEN recent_maintenance_count >= 2 THEN '🟡 Post-maintenance instability'
        WHEN failures_at_worst_step >= 10 THEN '🟠 Systematic process issue at ' || most_failed_step
        ELSE '🔵 Further investigation needed'
    END as likely_root_cause
FROM batch_factors
ORDER BY yield_pct ASC;

-- ============================================================================
-- 3. EQUIPMENT LINEAGE FOR FAILED WAFERS
-- ============================================================================
-- Purpose: Identify which equipment combo produces failures
-- Use Case: Equipment matching and scheduling optimization

WITH failed_wafer_equipment AS (
    SELECT 
        wt.wafer_id,
        wt.batch_id,
        GROUP_CONCAT(DISTINCT wt.equipment_id ORDER BY wt.process_step_id) as equipment_sequence,
        SUM(CASE WHEN wt.pass_fail = 'FAIL' THEN 1 ELSE 0 END) as failure_count
    FROM fact_wafer_tests wt
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY wt.wafer_id, wt.batch_id
    HAVING failure_count > 0
)
SELECT 
    equipment_sequence,
    COUNT(DISTINCT wafer_id) as failed_wafer_count,
    COUNT(DISTINCT batch_id) as affected_batches,
    ROUND(100.0 * COUNT(DISTINCT wafer_id) / 
          (SELECT COUNT(DISTINCT wafer_id) FROM fact_wafer_tests 
           WHERE test_timestamp >= CURRENT_DATE - INTERVAL '30 days'), 2) as pct_of_all_wafers,
    CASE 
        WHEN COUNT(DISTINCT wafer_id) >= 50 THEN '🔴 HIGH IMPACT COMBO'
        WHEN COUNT(DISTINCT wafer_id) >= 20 THEN '🟡 MODERATE IMPACT'
        ELSE '🟢 LOW IMPACT'
    END as severity
FROM failed_wafer_equipment
GROUP BY equipment_sequence
HAVING COUNT(DISTINCT wafer_id) >= 5  -- Filter noise
ORDER BY failed_wafer_count DESC
LIMIT 20;

-- ============================================================================
-- 4. TIME-TO-FAILURE ANALYSIS
-- ============================================================================
-- Purpose: At which process step do most failures occur?
-- Use Case: Identify early vs. late-stage yield loss

WITH wafer_failure_point AS (
    SELECT 
        wt.wafer_id,
        wt.batch_id,
        MIN(CASE WHEN wt.pass_fail = 'FAIL' THEN wt.process_step_id END) as first_failure_step,
        MAX(wt.process_step_id) as last_step_reached
    FROM fact_wafer_tests wt
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY wt.wafer_id, wt.batch_id
)
SELECT 
    ps.process_step_id,
    ps.process_step_name,
    ps.equipment_type,
    COUNT(DISTINCT wfp.wafer_id) as wafers_failed_at_step,
    ROUND(100.0 * COUNT(DISTINCT wfp.wafer_id) / 
          (SELECT COUNT(DISTINCT wafer_id) FROM wafer_failure_point 
           WHERE first_failure_step IS NOT NULL), 2) as pct_of_total_failures,
    ROUND(AVG(CASE WHEN wfp.first_failure_step IS NOT NULL 
                   THEN wfp.first_failure_step * 100.0 / wfp.last_step_reached 
                   END), 1) as avg_progress_pct_at_failure
FROM dim_process_steps ps
LEFT JOIN wafer_failure_point wfp ON ps.process_step_id = wfp.first_failure_step
WHERE wfp.first_failure_step IS NOT NULL
GROUP BY ps.process_step_id, ps.process_step_name, ps.equipment_type
ORDER BY wafers_failed_at_step DESC;

-- ============================================================================
-- 5. BATCH-TO-BATCH CORRELATION ANALYSIS
-- ============================================================================
-- Purpose: Do consecutive batches on same equipment show correlated failures?
-- Use Case: Process drift detection

WITH batch_sequence AS (
    SELECT 
        wt.batch_id,
        wt.equipment_id,
        wb.start_time,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
              COUNT(*), 2) as batch_yield,
        LAG(wb.start_time) OVER (PARTITION BY wt.equipment_id ORDER BY wb.start_time) as prev_batch_time,
        LAG(ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
                  COUNT(*), 2)) OVER (PARTITION BY wt.equipment_id ORDER BY wb.start_time) as prev_batch_yield
    FROM fact_wafer_tests wt
    JOIN dim_wafer_batches wb ON wt.batch_id = wb.batch_id
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY wt.batch_id, wt.equipment_id, wb.start_time
)
SELECT 
    equipment_id,
    COUNT(*) as batch_pairs_analyzed,
    ROUND(AVG(batch_yield), 2) as avg_yield,
    ROUND(CORR(prev_batch_yield, batch_yield), 3) as yield_autocorrelation,
    CASE 
        WHEN CORR(prev_batch_yield, batch_yield) > 0.7 
        THEN '🔴 STRONG CORRELATION - Process drift likely'
        WHEN CORR(prev_batch_yield, batch_yield) > 0.4
        THEN '🟡 MODERATE CORRELATION - Monitor'
        ELSE '🟢 INDEPENDENT BATCHES - Normal'
    END as interpretation
FROM batch_sequence
WHERE prev_batch_yield IS NOT NULL
GROUP BY equipment_id
HAVING COUNT(*) >= 10  -- Need sufficient data
ORDER BY yield_autocorrelation DESC;

-- ============================================================================
-- 6. MATERIAL TRACEABILITY (LOT-LEVEL)
-- ============================================================================
-- Purpose: Track all batches from a specific lot
-- Use Case: Supplier quality issues or material recall

-- Example: Replace 'LOT_2024_0156' with target lot
SELECT 
    wb.lot_number,
    wb.batch_id,
    wb.recipe,
    wb.start_time,
    wb.end_time,
    COUNT(DISTINCT wt.wafer_id) as wafer_count,
    SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed_wafers,
    ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
          COUNT(DISTINCT wt.wafer_id), 2) as batch_yield,
    -- Equipment used
    (SELECT GROUP_CONCAT(DISTINCT equipment_id ORDER BY process_step_id)
     FROM fact_wafer_tests wt2
     WHERE wt2.batch_id = wb.batch_id) as equipment_route,
    -- Current status
    CASE 
        WHEN wb.end_time > CURRENT_TIMESTAMP THEN 'IN PROGRESS'
        WHEN 100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
             COUNT(DISTINCT wt.wafer_id) >= 90 THEN 'RELEASED'
        WHEN 100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
             COUNT(DISTINCT wt.wafer_id) >= 70 THEN 'CONDITIONAL RELEASE'
        ELSE 'QUARANTINE'
    END as disposition
FROM dim_wafer_batches wb
LEFT JOIN fact_wafer_tests wt ON wb.batch_id = wt.batch_id
WHERE wb.lot_number = 'LOT_2024_0001'  -- << REPLACE WITH TARGET LOT
GROUP BY wb.lot_number, wb.batch_id, wb.recipe, wb.start_time, wb.end_time
ORDER BY wb.start_time DESC;

-- ============================================================================
-- 7. CROSS-BATCH CONTAMINATION DETECTION
-- ============================================================================
-- Purpose: Detect if sequential batches on equipment show failure patterns
-- Use Case: Chamber contamination or cross-contamination investigation

WITH sequential_batches AS (
    SELECT 
        wt.equipment_id,
        wt.batch_id,
        wb.start_time,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) as yield_pct,
        LAG(wt.batch_id) OVER (PARTITION BY wt.equipment_id ORDER BY wb.start_time) as prev_batch,
        LAG(ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2)) 
            OVER (PARTITION BY wt.equipment_id ORDER BY wb.start_time) as prev_yield,
        -- Check if maintenance happened between batches
        (SELECT COUNT(*)
         FROM maintenance_events me
         WHERE me.equipment_id = wt.equipment_id
           AND me.event_timestamp BETWEEN 
               LAG(wb.start_time) OVER (PARTITION BY wt.equipment_id ORDER BY wb.start_time)
               AND wb.start_time) as maintenance_between
    FROM fact_wafer_tests wt
    JOIN dim_wafer_batches wb ON wt.batch_id = wb.batch_id
    WHERE wb.start_time >= CURRENT_DATE - INTERVAL '14 days'
    GROUP BY wt.equipment_id, wt.batch_id, wb.start_time
)
SELECT 
    equipment_id,
    batch_id,
    prev_batch,
    yield_pct as current_yield,
    prev_yield,
    ROUND(yield_pct - prev_yield, 2) as yield_delta,
    maintenance_between,
    CASE 
        WHEN prev_yield < 80 AND yield_pct < 80 AND maintenance_between = 0
        THEN '🔴 POSSIBLE CONTAMINATION - No cleaning between low-yield batches'
        WHEN prev_yield >= 90 AND yield_pct < 80 AND maintenance_between = 0
        THEN '🟠 SUDDEN DROP - Investigate chamber condition'
        WHEN prev_yield < 85 AND yield_pct >= 90 AND maintenance_between >= 1
        THEN '🟢 MAINTENANCE EFFECTIVE'
        ELSE '⚪ NORMAL VARIATION'
    END as contamination_risk
FROM sequential_batches
WHERE prev_batch IS NOT NULL
ORDER BY equipment_id, start_time DESC;
