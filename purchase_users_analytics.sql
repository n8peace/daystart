-- Purchase Users Analytics Queries
-- Generated for DayStart purchase_users table implementation

-- =======================
-- Basic User Analytics
-- =======================

-- Total active users (last 30 days)
SELECT COUNT(DISTINCT receipt_id) as active_users_30d
FROM purchase_users
WHERE last_seen >= NOW() - INTERVAL '30 days';

-- User breakdown by test vs production
SELECT 
  is_test,
  COUNT(*) as user_count,
  COUNT(*) * 100.0 / SUM(COUNT(*)) OVER() as percentage
FROM purchase_users
GROUP BY is_test;

-- Daily active users trend (last 30 days)
SELECT 
  DATE(last_seen) as date,
  COUNT(DISTINCT receipt_id) as daily_active_users
FROM purchase_users
WHERE last_seen >= NOW() - INTERVAL '30 days'
GROUP BY DATE(last_seen)
ORDER BY date DESC;

-- New user registrations by day (last 30 days)
SELECT 
  DATE(created_at) as registration_date,
  COUNT(*) as new_users,
  COUNT(*) FILTER (WHERE is_test = false) as production_users,
  COUNT(*) FILTER (WHERE is_test = true) as test_users
FROM purchase_users
WHERE created_at >= NOW() - INTERVAL '30 days'
GROUP BY DATE(created_at)
ORDER BY registration_date DESC;

-- =======================
-- User Retention Analysis
-- =======================

-- User activity recency distribution
SELECT 
  CASE 
    WHEN last_seen >= NOW() - INTERVAL '1 day' THEN 'Last 24 hours'
    WHEN last_seen >= NOW() - INTERVAL '7 days' THEN 'Last week'
    WHEN last_seen >= NOW() - INTERVAL '30 days' THEN 'Last month'
    WHEN last_seen >= NOW() - INTERVAL '90 days' THEN 'Last 3 months'
    ELSE 'Inactive (90+ days)'
  END as activity_bucket,
  COUNT(*) as user_count
FROM purchase_users
WHERE is_test = false  -- Production users only
GROUP BY 
  CASE 
    WHEN last_seen >= NOW() - INTERVAL '1 day' THEN 'Last 24 hours'
    WHEN last_seen >= NOW() - INTERVAL '7 days' THEN 'Last week'
    WHEN last_seen >= NOW() - INTERVAL '30 days' THEN 'Last month'
    WHEN last_seen >= NOW() - INTERVAL '90 days' THEN 'Last 3 months'
    ELSE 'Inactive (90+ days)'
  END
ORDER BY 
  CASE 
    WHEN activity_bucket = 'Last 24 hours' THEN 1
    WHEN activity_bucket = 'Last week' THEN 2
    WHEN activity_bucket = 'Last month' THEN 3
    WHEN activity_bucket = 'Last 3 months' THEN 4
    ELSE 5
  END;

-- Average days between first and last seen
SELECT 
  AVG(EXTRACT(days FROM last_seen - created_at)) as avg_user_lifespan_days,
  PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY EXTRACT(days FROM last_seen - created_at)) as median_user_lifespan_days
FROM purchase_users
WHERE is_test = false
  AND last_seen > created_at;

-- =======================
-- Business Intelligence
-- =======================

-- Monthly user growth
SELECT 
  DATE_TRUNC('month', created_at) as month,
  COUNT(*) as new_users,
  SUM(COUNT(*)) OVER (ORDER BY DATE_TRUNC('month', created_at)) as cumulative_users
FROM purchase_users
WHERE is_test = false
GROUP BY DATE_TRUNC('month', created_at)
ORDER BY month DESC;

-- User activity by day of week
SELECT 
  EXTRACT(dow FROM last_seen) as day_of_week,
  CASE EXTRACT(dow FROM last_seen)
    WHEN 0 THEN 'Sunday'
    WHEN 1 THEN 'Monday'
    WHEN 2 THEN 'Tuesday'
    WHEN 3 THEN 'Wednesday'
    WHEN 4 THEN 'Thursday'
    WHEN 5 THEN 'Friday'
    WHEN 6 THEN 'Saturday'
  END as day_name,
  COUNT(*) as activity_count
FROM purchase_users
WHERE last_seen >= NOW() - INTERVAL '30 days'
  AND is_test = false
GROUP BY EXTRACT(dow FROM last_seen)
ORDER BY day_of_week;

-- =======================
-- Data Quality Checks
-- =======================

-- Check for duplicate receipt IDs (should be 0)
SELECT COUNT(*) as duplicate_receipts
FROM (
  SELECT receipt_id, COUNT(*) as count
  FROM purchase_users
  GROUP BY receipt_id
  HAVING COUNT(*) > 1
) duplicates;

-- Users with unusual last_seen times (future dates)
SELECT COUNT(*) as future_last_seen_count
FROM purchase_users
WHERE last_seen > NOW();

-- Test users in production data check
SELECT 
  COUNT(*) FILTER (WHERE receipt_id LIKE 'tx_%' AND is_test = false) as test_receipts_marked_production,
  COUNT(*) FILTER (WHERE receipt_id NOT LIKE 'tx_%' AND is_test = true) as production_receipts_marked_test
FROM purchase_users;

-- =======================
-- Performance Monitoring
-- =======================

-- Table size and performance metrics
SELECT 
  COUNT(*) as total_records,
  MIN(created_at) as earliest_user,
  MAX(created_at) as latest_user,
  MAX(last_seen) as most_recent_activity
FROM purchase_users;