# DayStart Backend

Production-ready Supabase backend for the DayStart morning briefing iOS app.

## Architecture

- **Database**: PostgreSQL with Row Level Security
- **Functions**: Supabase Edge Functions (Deno/TypeScript)
- **Storage**: Private bucket for audio files with signed URLs
- **Queue**: Database-based job queue with worker leasing
- **APIs**: OpenAI GPT-4o, ElevenLabs, NewsAPI, Alpha Vantage, etc.

## Quick Start

1. **Environment Setup**:
   ```bash
   npm install -g supabase
   supabase login
   supabase link --project-ref YOUR_PROJECT_ID
   ```

2. **Deploy Database Schema**:
   ```bash
   supabase db reset
   ```

3. **Deploy Functions**:
   ```bash
   supabase functions deploy
   ```

4. **Setup Environment Variables**:
   - Copy environment variables to Supabase Edge Function secrets
   - Configure GitHub Actions secrets

## Development

- **Local Development**: `supabase start`
- **Function Testing**: `supabase functions serve`
- **Database Changes**: Create migration with `supabase migration new`

## Production Deployment

All deployments happen via GitHub Actions. Never deploy directly to production.

- Push to `main` branch → Automatic deployment
- Functions and database migrations deployed together
- Environment variables managed via GitHub Secrets

## Monitoring

- Health checks via cron-job.org
- Comprehensive logging to `logs` table
- Email alerts for critical issues via Resend

## API Endpoints

- `POST /functions/v1/job_upsert_next_run` - Create user job (called by iOS app)
- `GET /functions/v1/get_user_audio` - Get signed URL for audio file
- `POST /functions/v1/cron_*` - Background jobs (called by cron-job.org)
- `POST /functions/v1/worker_*` - Job processors (called by scheduled workers)

See `claude-supabase.md` for complete documentation.