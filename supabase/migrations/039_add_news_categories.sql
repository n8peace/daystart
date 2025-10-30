-- Add news category preferences support
-- Add selected_news_categories column to jobs table for granular news filtering

-- Add selected_news_categories column with backward-compatible default
-- Default includes all major news categories for existing functionality
ALTER TABLE jobs ADD COLUMN IF NOT EXISTS selected_news_categories TEXT[] DEFAULT ARRAY['World', 'Business', 'Technology', 'Politics', 'Science'];

-- Add comment for documentation
COMMENT ON COLUMN jobs.selected_news_categories IS 'Array of selected news categories for content filtering. Default includes all categories for backward compatibility.';

-- Update the jobs table comment to reflect the new column
COMMENT ON TABLE jobs IS 'Core job queue for DayStart generation with user preferences captured at creation time, including sports and news filtering preferences';