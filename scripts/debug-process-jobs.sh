#!/bin/bash

# Debug script for process_jobs failures
# Collects comprehensive debugging information

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_section() {
    echo -e "\n${BLUE}=== ${1} ===${NC}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} ${1}"
}

# Check environment
if [[ -z "${SUPABASE_PROJECT_REF:-}" ]] || [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
    log_error "Missing required environment variables"
    exit 1
fi

JOB_ID="${1:-}"
if [[ -z "${JOB_ID}" ]]; then
    log_error "Usage: $0 <job_id>"
    exit 1
fi

OUTPUT_FILE="debug-job-${JOB_ID}-$(date +%Y%m%d_%H%M%S).log"

{
    echo "Process Jobs Debug Report"
    echo "========================="
    echo "Generated: $(date)"
    echo "Job ID: ${JOB_ID}"
    echo ""
    
    log_section "Job Details"
    curl -s -X GET \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/jobs?id=eq.${JOB_ID}" | jq '.'
    
    log_section "Job Snapshots"
    curl -s -X GET \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/job_snapshots?job_id=eq.${JOB_ID}" | jq '.'
    
    log_section "Recent Process Jobs Function Logs"
    if command -v supabase >/dev/null 2>&1; then
        supabase functions logs process_jobs --limit 50 2>&1 || echo "Unable to fetch function logs"
    else
        echo "Supabase CLI not available for log fetching"
    fi
    
    log_section "Content Cache Status"
    curl -s -X POST \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "Content-Type: application/json" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        -d '{"query":"SELECT source, COUNT(*) as count, MAX(cached_at) as latest FROM content_cache GROUP BY source"}' \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/rpc/query" 2>&1 || \
        echo "Unable to query content cache"
    
    log_section "Recent Failed Jobs"
    curl -s -X GET \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/jobs?status=eq.failed&order=created_at.desc&limit=5" | jq '.'
    
    log_section "System Health Check"
    # Check if process_jobs function is deployed
    echo "Checking process_jobs function deployment..."
    curl -s -I "https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/process_jobs" | head -n 5
    
    # Check database connectivity
    echo -e "\nChecking database connectivity..."
    curl -s -X GET \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/" | jq 'keys'
    
    log_section "Environment Configuration"
    echo "Checking function secrets configuration..."
    # This would show which secrets are set (not their values)
    if command -v supabase >/dev/null 2>&1; then
        supabase secrets list 2>&1 | grep -E "(OPENAI_API_KEY|ELEVENLABS_API_KEY|WORKER_AUTH_TOKEN)" || \
        echo "Unable to list secrets"
    fi
    
    log_section "Job Processing Timeline"
    # Get all status changes for this job
    curl -s -X GET \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "apikey: ${SUPABASE_ANON_KEY}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/jobs?id=eq.${JOB_ID}&select=created_at,updated_at,status,error_message,lease_expires_at" | jq '.'
    
} > "${OUTPUT_FILE}" 2>&1

echo -e "${GREEN}Debug report generated:${NC} ${OUTPUT_FILE}"
echo ""
echo "Key areas to check:"
echo "1. Job error_message field for specific failure reason"
echo "2. Function logs for runtime errors"
echo "3. Content cache status - ensure fresh content is available"
echo "4. Environment secrets - ensure all API keys are configured"
echo "5. Job snapshots for intermediate processing state"