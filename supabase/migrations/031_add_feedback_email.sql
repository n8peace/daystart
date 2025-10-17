-- Migration: 031_add_feedback_email
-- Adds optional email field to app_feedback table for user contact information

ALTER TABLE app_feedback ADD COLUMN email TEXT;