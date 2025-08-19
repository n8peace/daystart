-- Add tts_provider column to track which TTS service was used
ALTER TABLE jobs 
ADD COLUMN tts_provider TEXT DEFAULT 'elevenlabs';

-- Add comment for documentation
COMMENT ON COLUMN jobs.tts_provider IS 'TTS service used: elevenlabs or openai';

-- Update any existing rows to have the default value (optional, but good practice)
UPDATE jobs 
SET tts_provider = 'elevenlabs' 
WHERE tts_provider IS NULL;