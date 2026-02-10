-- Equipment Health Monitoring Queries
-- Predictive maintenance and equipment performance analytics

-- ============================================================================
-- 1. EQUIPMENT UPTIME & AVAILABILITY
-- ============================================================================
-- Purpose: Monitor equipment reliability and schedule preventive maintenance
-- Use Case: Daily equipment health dashboard

WITH equipment_status_summary AS (
    SELECT 
        ee.equipment_id,
        e.equipment_type,
        e.manufacturer,
        DATE(ee.event_timestamp) as date,
        COUNT(*) as total_events,
        SUM(CASE WHEN ee.status = 'RUNNING' THEN 1 ELSE 0 END) as running_events,
        SUM(CASE WHEN ee.status = 'IDLE' THEN 1 ELSE 0 END) as idle_events,
        SUM(CASE WHEN ee.status = 'ALARM' THEN 1 ELSE 0 END) as alarm_events,
        SUM(CASE WHEN ee.status = 'DOWN' THEN 1 ELSE 0 END) as down_events
    FROM fact_equipment_events ee
    JOIN dim_equipment e ON ee.equipment_id = e.equipment_id
    WHERE ee.event_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY ee.equipment_id, e.equipment_type, e.manufacturer, DATE(ee.event_timestamp)
)
SELECT 
    equipment_id,
    equipment_type,
    manufacturer,
    AVG(running_events * 100.0 / total_events) as avg_uptime_pct,
    AVG(alarm_events * 100.0 / total_events) as avg_alarm_rate_pct,
    AVG(down_events * 100.0 / total_events) as avg_downtime_pct,
    SUM(alarm_events) as total_alarms_30d,
    SUM(down_events) as total_down_events_30d,
    CASE 
        WHEN AVG(running_events * 100.0 / total_events) >= 95 THEN '🟢 EXCELLENT'
        WHEN AVG(running_events * 100.0 / total_events) >= 90 THEN '🟡 GOOD'
        WHEN AVG(running_events * 100.0 / total_events) >= 85 THEN '🟠 ACCEPTABLE'
        ELSE '🔴 NEEDS ATTENTION'
    END as health_status
FROM equipment_status_summary
GROUP BY equipment_id, equipment_type, manufacturer
ORDER BY avg_uptime_pct ASC;

-- ============================================================================
-- 2. MEAN TIME BETWEEN FAILURES (MTBF)
-- ============================================================================
-- Purpose: Reliability metric for equipment performance
-- Use Case: Maintenance optimization and warranty claims

WITH failure_events AS (
    SELECT 
        equipment_id,
        event_timestamp,
        status,
        LAG(event_timestamp) OVER (PARTITION BY equipment_id ORDER BY event_timestamp) as prev_event_time
    FROM fact_equipment_events
    WHERE status = 'DOWN'
      AND event_timestamp >= CURRENT_DATE - INTERVAL '90 days'
),
time_between_failures AS (
    SELECT 
        equipment_id,
        TIMESTAMPDIFF(HOUR, prev_event_time, event_timestamp) as hours_between_failures
    FROM failure_events
    WHERE prev_event_time IS NOT NULL
)
SELECT 
    e.equipment_id,
    e.equipment_type,
    e.manufacturer,
    DATEDIFF(CURRENT_DATE, e.install_date) as age_days,
    COUNT(tbf.hours_between_failures) as failure_count,
    ROUND(AVG(tbf.hours_between_failures), 1) as mtbf_hours,
    ROUND(AVG(tbf.hours_between_failures) / 24, 1) as mtbf_days,
    CASE 
        WHEN AVG(tbf.hours_between_failures) >= 720 THEN '🟢 EXCELLENT (>30 days)'
        WHEN AVG(tbf.hours_between_failures) >= 360 THEN '🟡 GOOD (15-30 days)'
        WHEN AVG(tbf.hours_between_failures) >= 168 THEN '🟠 ACCEPTABLE (7-15 days)'
        ELSE '🔴 POOR (<7 days)'
    END as reliability_rating
FROM dim_equipment e
LEFT JOIN time_between_failures tbf ON e.equipment_id = tbf.equipment_id
WHERE e.status = 'ACTIVE'
GROUP BY e.equipment_id, e.equipment_type, e.manufacturer, e.install_date
ORDER BY mtbf_hours ASC NULLS LAST;

-- ============================================================================
-- 3. ALARM FREQUENCY & ROOT CAUSE ANALYSIS
-- ============================================================================
-- Purpose: Identify chronic alarm conditions
-- Use Case: Preventive maintenance prioritization

WITH alarm_analysis AS (
    SELECT 
        ee.equipment_id,
        e.equipment_type,
        DATE(ee.event_timestamp) as date,
        COUNT(*) as alarm_count,
        -- Categorize by sensor readings during alarm
        AVG(ee.temperature_c) as avg_temp_during_alarm,
        AVG(ee.pressure_torr) as avg_pressure_during_alarm,
        STDDEV(ee.temperature_c) as temp_std,
        STDDEV(ee.pressure_torr) as pressure_std
    FROM fact_equipment_events ee
    JOIN dim_equipment e ON ee.equipment_id = e.equipment_id
    WHERE ee.status = 'ALARM'
      AND ee.event_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    GROUP BY ee.equipment_id, e.equipment_type, DATE(ee.event_timestamp)
)
SELECT 
    equipment_id,
    equipment_type,
    COUNT(DISTINCT date) as days_with_alarms,
    SUM(alarm_count) as total_alarms,
    ROUND(AVG(alarm_count), 1) as avg_alarms_per_day,
    ROUND(AVG(avg_temp_during_alarm), 1) as avg_alarm_temperature,
    ROUND(AVG(temp_std), 2) as temp_variability,
    CASE 
        WHEN SUM(alarm_count) >= 100 THEN '🔴 CRITICAL - Immediate intervention needed'
        WHEN SUM(alarm_count) >= 50 THEN '🟠 HIGH - Schedule maintenance'
        WHEN SUM(alarm_count) >= 20 THEN '🟡 MEDIUM - Monitor closely'
        ELSE '🟢 LOW - Normal operations'
    END as alarm_severity
FROM alarm_analysis
GROUP BY equipment_id, equipment_type
HAVING SUM(alarm_count) >= 10  -- Filter noise
ORDER BY total_alarms DESC;

-- ============================================================================
-- 4. EQUIPMENT DEGRADATION DETECTION
-- ============================================================================
-- Purpose: Detect gradual performance degradation before failure
-- Use Case: Predictive maintenance scheduling

WITH weekly_sensor_metrics AS (
    SELECT 
        ee.equipment_id,
        e.equipment_type,
        YEARWEEK(ee.event_timestamp) as year_week,
        AVG(ee.temperature_c) as avg_temp,
        STDDEV(ee.temperature_c) as temp_std,
        AVG(ee.pressure_torr) as avg_pressure,
        STDDEV(ee.pressure_torr) as pressure_std,
        COUNT(CASE WHEN ee.status = 'ALARM' THEN 1 END) as alarm_count
    FROM fact_equipment_events ee
    JOIN dim_equipment e ON ee.equipment_id = e.equipment_id
    WHERE ee.event_timestamp >= CURRENT_DATE - INTERVAL '12 weeks'
      AND ee.status IN ('RUNNING', 'ALARM')
    GROUP BY ee.equipment_id, e.equipment_type, YEARWEEK(ee.event_timestamp)
),
degradation_trend AS (
    SELECT 
        equipment_id,
        equipment_type,
        year_week,
        avg_temp,
        temp_std,
        avg_pressure,
        pressure_std,
        alarm_count,
        -- Calculate trend using linear regression approximation
        AVG(temp_std) OVER (PARTITION BY equipment_id ORDER BY year_week 
                           ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) as temp_std_4wk_avg,
        AVG(alarm_count) OVER (PARTITION BY equipment_id ORDER BY year_week 
                              ROWS BETWEEN 3 PRECEDING AND CURRENT ROW) as alarm_4wk_avg
    FROM weekly_sensor_metrics
)
SELECT 
    equipment_id,
    equipment_type,
    MAX(year_week) as latest_week,
    ROUND(AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                   THEN temp_std END), 3) as current_temp_variability,
    ROUND(AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                   THEN temp_std_4wk_avg END), 3) as baseline_temp_variability,
    AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
             THEN alarm_count END) as current_week_alarms,
    ROUND(AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                   THEN alarm_4wk_avg END), 1) as baseline_alarms,
    CASE 
        WHEN AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                      THEN temp_std END) > 
             AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                      THEN temp_std_4wk_avg END) * 1.5 
             AND AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                          THEN alarm_count END) > 
                 AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                          THEN alarm_4wk_avg END) * 2
        THEN '🔴 HIGH RISK - Degradation detected'
        WHEN AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                      THEN temp_std END) > 
             AVG(CASE WHEN year_week = (SELECT MAX(year_week) FROM degradation_trend WHERE equipment_id = dt.equipment_id)
                      THEN temp_std_4wk_avg END) * 1.2
        THEN '🟡 MODERATE RISK - Monitor closely'
        ELSE '🟢 STABLE'
    END as degradation_status
FROM degradation_trend dt
GROUP BY equipment_id, equipment_type
ORDER BY degradation_status ASC, equipment_id;

-- ============================================================================
-- 5. MAINTENANCE EFFECTIVENESS ANALYSIS
-- ============================================================================
-- Purpose: Measure if maintenance improves equipment performance
-- Use Case: Maintenance program ROI analysis

WITH maintenance_periods AS (
    SELECT 
        me.equipment_id,
        me.event_type,
        me.event_timestamp as maintenance_time,
        me.duration_hours,
        LEAD(me.event_timestamp) OVER (PARTITION BY me.equipment_id ORDER BY me.event_timestamp) as next_maintenance
    FROM maintenance_events me
    WHERE me.event_timestamp >= CURRENT_DATE - INTERVAL '90 days'
),
pre_post_metrics AS (
    SELECT 
        mp.equipment_id,
        mp.event_type,
        mp.maintenance_time,
        -- 7 days before maintenance
        (SELECT AVG(CASE WHEN ee.status = 'ALARM' THEN 1 ELSE 0 END)
         FROM fact_equipment_events ee
         WHERE ee.equipment_id = mp.equipment_id
           AND ee.event_timestamp BETWEEN mp.maintenance_time - INTERVAL '7 days' 
                                      AND mp.maintenance_time) as pre_alarm_rate,
        -- 7 days after maintenance
        (SELECT AVG(CASE WHEN ee.status = 'ALARM' THEN 1 ELSE 0 END)
         FROM fact_equipment_events ee
         WHERE ee.equipment_id = mp.equipment_id
           AND ee.event_timestamp BETWEEN mp.maintenance_time 
                                      AND mp.maintenance_time + INTERVAL '7 days') as post_alarm_rate,
        -- Yield impact
        (SELECT AVG(CASE WHEN wt.pass_fail = 'PASS' THEN 100.0 ELSE 0 END)
         FROM fact_wafer_tests wt
         WHERE wt.equipment_id = mp.equipment_id
           AND wt.test_timestamp BETWEEN mp.maintenance_time - INTERVAL '7 days'
                                     AND mp.maintenance_time) as pre_yield,
        (SELECT AVG(CASE WHEN wt.pass_fail = 'PASS' THEN 100.0 ELSE 0 END)
         FROM fact_wafer_tests wt
         WHERE wt.equipment_id = mp.equipment_id
           AND wt.test_timestamp BETWEEN mp.maintenance_time
                                     AND mp.maintenance_time + INTERVAL '7 days') as post_yield
    FROM maintenance_periods mp
)
SELECT 
    equipment_id,
    event_type,
    COUNT(*) as maintenance_count,
    ROUND(AVG(pre_alarm_rate * 100), 2) as avg_pre_alarm_rate_pct,
    ROUND(AVG(post_alarm_rate * 100), 2) as avg_post_alarm_rate_pct,
    ROUND(AVG((post_alarm_rate - pre_alarm_rate) * 100), 2) as alarm_rate_change_pct,
    ROUND(AVG(pre_yield), 2) as avg_pre_yield,
    ROUND(AVG(post_yield), 2) as avg_post_yield,
    ROUND(AVG(post_yield - pre_yield), 2) as yield_improvement,
    CASE 
        WHEN AVG(post_alarm_rate) < AVG(pre_alarm_rate) * 0.7 AND AVG(post_yield) > AVG(pre_yield)
        THEN '🟢 HIGHLY EFFECTIVE'
        WHEN AVG(post_alarm_rate) < AVG(pre_alarm_rate)
        THEN '🟡 MODERATELY EFFECTIVE'
        ELSE '🔴 LIMITED EFFECTIVENESS'
    END as maintenance_effectiveness
FROM pre_post_metrics
WHERE pre_alarm_rate IS NOT NULL AND post_alarm_rate IS NOT NULL
GROUP BY equipment_id, event_type
ORDER BY yield_improvement DESC;

-- ============================================================================
-- 6. EQUIPMENT RANKING BY CRITICALITY
-- ============================================================================
-- Purpose: Prioritize which equipment to monitor most closely
-- Use Case: Resource allocation for maintenance teams

WITH equipment_impact AS (
    SELECT 
        e.equipment_id,
        e.equipment_type,
        e.manufacturer,
        -- Usage intensity
        COUNT(DISTINCT wt.batch_id) as batches_processed_30d,
        COUNT(DISTINCT wt.wafer_id) as wafers_processed_30d,
        -- Quality impact
        AVG(CASE WHEN wt.pass_fail = 'PASS' THEN 100.0 ELSE 0 END) as avg_yield,
        -- Reliability
        (SELECT COUNT(*) FROM fact_equipment_events ee2 
         WHERE ee2.equipment_id = e.equipment_id 
           AND ee2.status = 'DOWN'
           AND ee2.event_timestamp >= CURRENT_DATE - INTERVAL '30 days') as down_events,
        -- Financial impact (simplified - wafers processed * assumed value)
        COUNT(DISTINCT wt.wafer_id) * 1000 as estimated_value_processed
    FROM dim_equipment e
    LEFT JOIN fact_wafer_tests wt ON e.equipment_id = wt.equipment_id
        AND wt.test_timestamp >= CURRENT_DATE - INTERVAL '30 days'
    WHERE e.status = 'ACTIVE'
    GROUP BY e.equipment_id, e.equipment_type, e.manufacturer
)
SELECT 
    equipment_id,
    equipment_type,
    manufacturer,
    batches_processed_30d,
    wafers_processed_30d,
    ROUND(avg_yield, 2) as yield_pct,
    down_events,
    estimated_value_processed,
    -- Criticality score: (usage * yield impact * reliability)
    ROUND((wafers_processed_30d / 100.0) * (100 - avg_yield) * (1 + down_events), 2) as criticality_score,
    CASE 
        WHEN (wafers_processed_30d / 100.0) * (100 - avg_yield) * (1 + down_events) > 500 
        THEN '🔴 TIER 1 - Critical Equipment'
        WHEN (wafers_processed_30d / 100.0) * (100 - avg_yield) * (1 + down_events) > 200
        THEN '🟠 TIER 2 - Important Equipment'
        WHEN (wafers_processed_30d / 100.0) * (100 - avg_yield) * (1 + down_events) > 50
        THEN '🟡 TIER 3 - Standard Equipment'
        ELSE '🟢 TIER 4 - Low Impact Equipment'
    END as criticality_tier
FROM equipment_impact
ORDER BY criticality_score DESC;
