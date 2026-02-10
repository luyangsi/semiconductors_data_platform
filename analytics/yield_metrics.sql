-- Yield Metrics Analysis Queries
-- Production-grade SQL for semiconductor manufacturing analytics

-- ============================================================================
-- 1. OVERALL YIELD BY EQUIPMENT
-- ============================================================================
-- Purpose: Identify underperforming equipment that impacts yield
-- Use Case: Daily yield monitoring dashboard

WITH equipment_yield AS (
    SELECT 
        e.equipment_id,
        e.equipment_type,
        e.manufacturer,
        COUNT(DISTINCT wt.wafer_id) as total_wafers_processed,
        SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed_wafers,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT wt.wafer_id), 2) as yield_pct,
        MIN(wt.test_timestamp) as first_test,
        MAX(wt.test_timestamp) as last_test
    FROM fact_wafer_tests wt
    JOIN dim_equipment e ON wt.equipment_id = e.equipment_id
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY e.equipment_id, e.equipment_type, e.manufacturer
    HAVING COUNT(DISTINCT wt.wafer_id) >= 30  -- Statistical significance
)
SELECT 
    equipment_id,
    equipment_type,
    manufacturer,
    total_wafers_processed,
    passed_wafers,
    yield_pct,
    CASE 
        WHEN yield_pct >= 95 THEN 'EXCELLENT'
        WHEN yield_pct >= 90 THEN 'GOOD'
        WHEN yield_pct >= 85 THEN 'ACCEPTABLE'
        ELSE 'NEEDS ATTENTION'
    END as performance_tier,
    DATEDIFF(last_test, first_test) as days_in_operation
FROM equipment_yield
ORDER BY yield_pct ASC;  -- Worst performers first

-- ============================================================================
-- 2. YIELD TREND OVER TIME (DRIFT DETECTION)
-- ============================================================================
-- Purpose: Detect process drift or equipment degradation
-- Use Case: Weekly yield review meetings

WITH daily_yield AS (
    SELECT 
        DATE(wt.test_timestamp) as test_date,
        e.equipment_type,
        COUNT(DISTINCT wt.wafer_id) as wafers,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT wt.wafer_id), 2) as yield_pct
    FROM fact_wafer_tests wt
    JOIN dim_equipment e ON wt.equipment_id = e.equipment_id
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY DATE(wt.test_timestamp), e.equipment_type
    HAVING COUNT(DISTINCT wt.wafer_id) >= 20
),
yield_with_moving_avg AS (
    SELECT 
        test_date,
        equipment_type,
        wafers,
        yield_pct,
        AVG(yield_pct) OVER (
            PARTITION BY equipment_type 
            ORDER BY test_date 
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ) as yield_7day_ma,
        AVG(yield_pct) OVER (
            PARTITION BY equipment_type
        ) as overall_avg_yield
    FROM daily_yield
)
SELECT 
    test_date,
    equipment_type,
    wafers,
    yield_pct,
    yield_7day_ma,
    overall_avg_yield,
    ROUND(yield_pct - yield_7day_ma, 2) as deviation_from_trend,
    CASE 
        WHEN yield_pct < overall_avg_yield - 5 THEN '🔴 SIGNIFICANT DROP'
        WHEN yield_pct < overall_avg_yield - 2 THEN '🟡 MINOR DROP'
        WHEN yield_pct > overall_avg_yield + 2 THEN '🟢 IMPROVED'
        ELSE '⚪ STABLE'
    END as trend_status
FROM yield_with_moving_avg
ORDER BY test_date DESC, equipment_type;

-- ============================================================================
-- 3. YIELD BY PROCESS STEP
-- ============================================================================
-- Purpose: Identify which process steps have the highest failure rates
-- Use Case: Root cause analysis for yield loss

SELECT 
    ps.process_step_id,
    ps.process_step_name,
    ps.equipment_type,
    COUNT(DISTINCT wt.wafer_id) as wafers_tested,
    SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed,
    SUM(CASE WHEN wt.pass_fail = 'FAIL' THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'FAIL' THEN 1 ELSE 0 END) / 
          COUNT(*), 2) as failure_rate_pct,
    AVG(wt.defect_density) as avg_defect_density,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, wt.start_time, wt.end_time) / 60.0), 1) as avg_duration_min
FROM fact_wafer_tests wt
JOIN dim_process_steps ps ON wt.process_step_id = ps.process_step_id
WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
GROUP BY ps.process_step_id, ps.process_step_name, ps.equipment_type
ORDER BY failure_rate_pct DESC;

-- ============================================================================
-- 4. BATCH-LEVEL YIELD ANALYSIS
-- ============================================================================
-- Purpose: Find problematic batches and their characteristics
-- Use Case: Quality investigation and lot disposition

WITH batch_metrics AS (
    SELECT 
        wb.batch_id,
        wb.lot_number,
        wb.recipe,
        wb.start_time,
        COUNT(DISTINCT wt.wafer_id) as wafer_count,
        SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) as passed_wafers,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / 
              COUNT(DISTINCT wt.wafer_id), 2) as batch_yield_pct,
        AVG(wt.defect_density) as avg_defect_density,
        STRING_AGG(DISTINCT wt.equipment_id, ', ') as equipment_used
    FROM dim_wafer_batches wb
    JOIN fact_wafer_tests wt ON wb.batch_id = wt.batch_id
    WHERE wb.start_time >= CURRENT_DATE - INTERVAL '7 days'
    GROUP BY wb.batch_id, wb.lot_number, wb.recipe, wb.start_time
)
SELECT 
    batch_id,
    lot_number,
    recipe,
    DATE(start_time) as batch_date,
    wafer_count,
    passed_wafers,
    batch_yield_pct,
    ROUND(avg_defect_density, 3) as avg_defect_density,
    equipment_used,
    CASE 
        WHEN batch_yield_pct >= 95 THEN 'EXCELLENT'
        WHEN batch_yield_pct >= 90 THEN 'GOOD'
        WHEN batch_yield_pct >= 80 THEN 'MARGINAL'
        ELSE 'REJECT'
    END as disposition
FROM batch_metrics
ORDER BY batch_yield_pct ASC, start_time DESC;

-- ============================================================================
-- 5. PARETO ANALYSIS OF DEFECT TYPES
-- ============================================================================
-- Purpose: 80/20 rule - identify top defect contributors
-- Use Case: Yield improvement prioritization

WITH defect_summary AS (
    SELECT 
        wt.bin_code,
        COUNT(*) as defect_count,
        ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) as pct_of_total
    FROM fact_wafer_tests wt
    WHERE wt.pass_fail = 'FAIL'
      AND wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY wt.bin_code
),
cumulative AS (
    SELECT 
        bin_code,
        defect_count,
        pct_of_total,
        SUM(pct_of_total) OVER (ORDER BY defect_count DESC) as cumulative_pct
    FROM defect_summary
)
SELECT 
    bin_code as defect_type,
    defect_count,
    pct_of_total,
    cumulative_pct,
    CASE 
        WHEN cumulative_pct <= 80 THEN '🔴 HIGH PRIORITY'
        WHEN cumulative_pct <= 95 THEN '🟡 MEDIUM PRIORITY'
        ELSE '🟢 LOW PRIORITY'
    END as improvement_priority
FROM cumulative
ORDER BY defect_count DESC;

-- ============================================================================
-- 6. FIRST-PASS YIELD (FPY) vs. FINAL YIELD
-- ============================================================================
-- Purpose: Measure rework impact
-- Use Case: Process efficiency analysis

WITH wafer_step_summary AS (
    SELECT 
        wt.wafer_id,
        wt.batch_id,
        MIN(CASE WHEN wt.process_step_id = 1 THEN wt.pass_fail END) as first_step_result,
        MAX(CASE WHEN wt.process_step_id = (SELECT MAX(process_step_id) FROM dim_process_steps) 
                 THEN wt.pass_fail END) as final_step_result
    FROM fact_wafer_tests wt
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY wt.wafer_id, wt.batch_id
)
SELECT 
    COUNT(*) as total_wafers,
    SUM(CASE WHEN first_step_result = 'PASS' THEN 1 ELSE 0 END) as first_pass_count,
    SUM(CASE WHEN final_step_result = 'PASS' THEN 1 ELSE 0 END) as final_pass_count,
    ROUND(100.0 * SUM(CASE WHEN first_step_result = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) as first_pass_yield,
    ROUND(100.0 * SUM(CASE WHEN final_step_result = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) as final_yield,
    ROUND(100.0 * (SUM(CASE WHEN final_step_result = 'PASS' THEN 1 ELSE 0 END) - 
                   SUM(CASE WHEN first_step_result = 'PASS' THEN 1 ELSE 0 END)) / 
          SUM(CASE WHEN first_step_result = 'FAIL' THEN 1 ELSE 0 END), 2) as rework_recovery_rate
FROM wafer_step_summary;

-- ============================================================================
-- 7. EQUIPMENT UTILIZATION vs. YIELD CORRELATION
-- ============================================================================
-- Purpose: Determine if high utilization degrades yield
-- Use Case: Capacity planning and maintenance scheduling

WITH equipment_utilization AS (
    SELECT 
        ee.equipment_id,
        DATE(ee.event_timestamp) as date,
        SUM(CASE WHEN ee.status = 'RUNNING' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) as utilization_pct
    FROM fact_equipment_events ee
    WHERE ee.event_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY ee.equipment_id, DATE(ee.event_timestamp)
),
daily_equipment_yield AS (
    SELECT 
        wt.equipment_id,
        DATE(wt.test_timestamp) as date,
        ROUND(100.0 * SUM(CASE WHEN wt.pass_fail = 'PASS' THEN 1 ELSE 0 END) / COUNT(*), 2) as yield_pct
    FROM fact_wafer_tests wt
    WHERE wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY wt.equipment_id, DATE(wt.test_timestamp)
    HAVING COUNT(*) >= 20
)
SELECT 
    u.equipment_id,
    AVG(u.utilization_pct) as avg_utilization,
    AVG(y.yield_pct) as avg_yield,
    CORR(u.utilization_pct, y.yield_pct) as utilization_yield_correlation,
    CASE 
        WHEN CORR(u.utilization_pct, y.yield_pct) < -0.5 THEN '⚠️ High utilization hurts yield'
        WHEN CORR(u.utilization_pct, y.yield_pct) < -0.3 THEN '🟡 Moderate negative correlation'
        ELSE '✅ No significant correlation'
    END as interpretation
FROM equipment_utilization u
JOIN daily_equipment_yield y ON u.equipment_id = y.equipment_id AND u.date = y.date
GROUP BY u.equipment_id
HAVING COUNT(*) >= 7  -- At least 1 week of data
ORDER BY utilization_yield_correlation ASC;
