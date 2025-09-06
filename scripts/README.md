# DayStart Scripts

This directory contains maintenance and debugging scripts for DayStart's Supabase backend.

## Scripts Overview

### Deployment
Deployment is handled by GitHub Actions workflow (`.github/workflows/deploy-supabase.yml`):
- Deploys database migrations and Edge Functions 
- Creates a test job to validate the `process_jobs` function
- Monitors test job for successful completion
- Automatically rolls back on failure
- Uploads debug logs as artifacts

### Utility Scripts

#### rollback-functions.sh
Git-based rollback script for Edge Functions:
- Finds the previous commit that modified Edge Functions
- Shows what will be reverted
- Creates a backup branch before rollback
- Redeploys the previous version
- Commits the rollback for audit trail

**Usage:**
```bash
# Set required environment variables
export SUPABASE_PROJECT_REF="your-project-ref"
export SUPABASE_ACCESS_TOKEN="your-access-token"

# Run rollback
./scripts/rollback-functions.sh
```

#### debug-process-jobs.sh
Comprehensive debugging tool for failed jobs:
- Fetches detailed job information
- Collects function logs
- Checks content cache status
- Verifies environment configuration
- Generates timestamped debug reports

**Usage:**
```bash
# Debug a specific job
./scripts/debug-process-jobs.sh <job-id>

# Output: debug-job-<job-id>-<timestamp>.log
```

## Workflow

### Normal Deployment
1. Push changes to `main` branch
2. GitHub Actions automatically:
   - Deploys to Supabase
   - Creates test job
   - Validates deployment
   - Rolls back if test fails

### Manual Operations
- **Manual Rollback:** `./scripts/rollback-functions.sh`  
- **Debug Failed Job:** `./scripts/debug-process-jobs.sh <job-id>`

## Environment Variables

For manual script usage, set these variables:
- `SUPABASE_PROJECT_REF`: Your Supabase project reference  
- `SUPABASE_ACCESS_TOKEN`: Supabase access token for CLI
- `SUPABASE_ANON_KEY`: Anonymous key for API calls (debug script only)

GitHub Actions uses these from repository secrets automatically.

## Troubleshooting

1. **Rollback fails:**
   - Ensure you're in the git repository root
   - Check for uncommitted changes  
   - Verify SUPABASE_ACCESS_TOKEN is valid

2. **Debug script errors:**
   - Confirm job ID exists
   - Check network connectivity to Supabase
   - Verify authentication credentials

3. **Deployment fails in GitHub Actions:**
   - Check repository secrets are configured
   - Review workflow logs and artifacts
   - Use debug script with failed job ID