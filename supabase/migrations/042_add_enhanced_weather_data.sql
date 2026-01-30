-- Add enhanced_weather_data column to jobs table
-- This column stores multi-location weather forecasts with travel detection and notable conditions
-- Backwards compatible: NULL means use simple weather_data field

ALTER TABLE jobs
ADD COLUMN enhanced_weather_data JSONB;

-- Add index for querying enhanced weather data
CREATE INDEX IF NOT EXISTS idx_jobs_enhanced_weather
ON jobs USING gin (enhanced_weather_data);

-- Add comment for documentation
COMMENT ON COLUMN jobs.enhanced_weather_data IS
'Enhanced weather forecasts including multi-location (travel destinations) and notable conditions. Structure: {currentLocation: string, currentForecast: [], travelForecasts: [], notableConditions: []}. NULL means fall back to simple weather_data.';
