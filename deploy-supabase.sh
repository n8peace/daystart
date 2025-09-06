#!/bin/bash

# DayStart Supabase Deployment Script with Test Job Validation
# This script deploys Supabase functions and validates the deployment with a test job

set -euo pipefail

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE="${SCRIPT_DIR}/deploy-$(date +%Y%m%d_%H%M%S).log"
TEST_RECEIPT_ID="test-deploy-$(date +%s)"
TEST_JOB_ID=""
MAX_WAIT_TIME=300  # 5 minutes
CHECK_INTERVAL=10  # Check every 10 seconds

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${1}" | tee -a "${LOG_FILE}"
}

log_info() {
    log "${BLUE}[INFO]${NC} ${1}"
}

log_success() {
    log "${GREEN}[SUCCESS]${NC} ${1}"
}

log_warning() {
    log "${YELLOW}[WARNING]${NC} ${1}"
}

log_error() {
    log "${RED}[ERROR]${NC} ${1}"
}

# Check required environment variables
check_env_vars() {
    local missing_vars=()
    
    [[ -z "${SUPABASE_PROJECT_REF:-}" ]] && missing_vars+=("SUPABASE_PROJECT_REF")
    [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]] && missing_vars+=("SUPABASE_ACCESS_TOKEN")
    [[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing_vars+=("SUPABASE_ANON_KEY")
    [[ -z "${SUPABASE_DB_PASSWORD:-}" ]] && missing_vars+=("SUPABASE_DB_PASSWORD")
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        log_error "Missing required environment variables: ${missing_vars[*]}"
        log_info "Please set these variables before running the script"
        exit 1
    fi
}

# Save current function versions for rollback
save_function_versions() {
    log_info "Saving current function versions for potential rollback..."
    
    # Get list of deployed functions with their current versions
    FUNCTIONS_BACKUP=$(mktemp)
    supabase functions list --json > "${FUNCTIONS_BACKUP}" 2>&1 || {
        log_warning "Could not save function versions, rollback will not be available"
        rm -f "${FUNCTIONS_BACKUP}"
        return 1
    }
    
    log_info "Function versions saved to: ${FUNCTIONS_BACKUP}"
    echo "${FUNCTIONS_BACKUP}"
}

# Deploy Supabase functions and migrations
deploy_supabase() {
    log_info "Starting Supabase deployment..."
    
    # Check if we're in the right directory
    if [[ ! -f "supabase/functions/process_jobs/index.ts" ]]; then
        log_error "Not in the DayStart project root directory!"
        log_error "Expected to find: supabase/functions/process_jobs/index.ts"
        log_error "Current directory: $(pwd)"
        return 1
    fi
    
    # Link project
    log_info "Linking Supabase project: ${SUPABASE_PROJECT_REF}"
    supabase link --project-ref "${SUPABASE_PROJECT_REF}" --password "${SUPABASE_DB_PASSWORD}" >> "${LOG_FILE}" 2>&1 || {
        log_error "Failed to link Supabase project"
        return 1
    }
    
    # Run migrations
    log_info "Running database migrations..."
    supabase db push >> "${LOG_FILE}" 2>&1 || {
        log_error "Failed to run database migrations"
        return 1
    }
    
    # Deploy functions
    log_info "Deploying Edge Functions..."
    supabase functions deploy >> "${LOG_FILE}" 2>&1 || {
        log_error "Failed to deploy Edge Functions"
        return 1
    }
    
    # Set secrets
    log_info "Setting function secrets..."
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        supabase secrets set OPENAI_API_KEY="${OPENAI_API_KEY}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -n "${ELEVENLABS_API_KEY:-}" ]]; then
        supabase secrets set ELEVENLABS_API_KEY="${ELEVENLABS_API_KEY}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -n "${WORKER_AUTH_TOKEN:-}" ]]; then
        supabase secrets set WORKER_AUTH_TOKEN="${WORKER_AUTH_TOKEN}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -n "${NEWSAPI_KEY:-}" ]]; then
        supabase secrets set NEWSAPI_KEY="${NEWSAPI_KEY}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -n "${GNEWS_API_KEY:-}" ]]; then
        supabase secrets set GNEWS_API_KEY="${GNEWS_API_KEY}" >> "${LOG_FILE}" 2>&1
    fi
    if [[ -n "${RAPIDAPI_KEY:-}" ]]; then
        supabase secrets set RAPIDAPI_KEY="${RAPIDAPI_KEY}" >> "${LOG_FILE}" 2>&1
    fi
    
    log_success "Deployment completed successfully"
    log_info "Deployment phase finished - proceeding to validation..."
    return 0
}

# Create a test job
create_test_job() {
    log_info "Creating test job to validate deployment..."
    log_info "Test receipt ID: ${TEST_RECEIPT_ID}"
    
    # macOS compatible date command
    local tomorrow
    if date -v +1d >/dev/null 2>&1; then
        # macOS
        tomorrow=$(date -v +1d +%Y-%m-%d)
    else
        # Linux
        tomorrow=$(date -d tomorrow +%Y-%m-%d)
    fi
    
    local scheduled_at="${tomorrow}T07:00:00Z"
    log_info "Test job scheduled for: ${scheduled_at}"
    
    local payload=$(cat <<EOF
{
    "local_date": "${tomorrow}",
    "scheduled_at": "${scheduled_at}",
    "preferred_name": "Deployment Test",
    "include_weather": false,
    "include_news": true,
    "include_sports": false,
    "include_stocks": false,
    "stock_symbols": [],
    "include_calendar": false,
    "include_quotes": true,
    "quote_preference": "motivational",
    "voice_option": "voice1",
    "daystart_length": 30,
    "timezone": "America/New_York",
    "test_mode": true
}
EOF
)
    
    log_info "Calling create_job endpoint..."
    log_info "URL: https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/create_job"
    
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
        -H "x-client-info: ${TEST_RECEIPT_ID}" \
        -H "x-auth-type: test-deploy" \
        -d "${payload}" \
        "https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/create_job" 2>&1)
    
    log_info "API Response: ${response}"
    
    # Extract job ID from response
    TEST_JOB_ID=$(echo "${response}" | grep -o '"id":"[^"]*' | cut -d'"' -f4)
    
    if [[ -z "${TEST_JOB_ID}" ]]; then
        log_error "Failed to create test job. Response: ${response}"
        # Try to extract error message
        local error_msg=$(echo "${response}" | grep -o '"error":"[^"]*' | cut -d'"' -f4)
        if [[ -n "${error_msg}" ]]; then
            log_error "Error message: ${error_msg}"
        fi
        return 1
    fi
    
    log_success "Test job created with ID: ${TEST_JOB_ID}"
    return 0
}

# Monitor job processing
monitor_job_processing() {
    log_info "Monitoring test job processing..."
    
    local start_time=$(date +%s)
    local job_status="pending"
    
    while [[ "${job_status}" != "completed" ]]; do
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))
        
        if [[ ${elapsed} -gt ${MAX_WAIT_TIME} ]]; then
            log_error "Job processing timeout after ${MAX_WAIT_TIME} seconds"
            return 1
        fi
        
        # Check job status
        local status_response=$(curl -s -X GET \
            -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
            -H "x-client-info: ${TEST_RECEIPT_ID}" \
            "https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1/get_audio_status?job_id=${TEST_JOB_ID}" 2>&1)
        
        job_status=$(echo "${status_response}" | grep -o '"status":"[^"]*' | cut -d'"' -f4)
        
        case "${job_status}" in
            "completed")
                log_success "Job completed successfully!"
                echo "${status_response}" >> "${LOG_FILE}"
                return 0
                ;;
            "failed")
                log_error "Job failed! Response: ${status_response}"
                
                # Get detailed job information
                log_info "Fetching detailed job information..."
                local job_details=$(curl -s -X GET \
                    -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
                    -H "x-client-info: ${TEST_RECEIPT_ID}" \
                    "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/jobs?id=eq.${TEST_JOB_ID}" 2>&1)
                
                echo "Job details: ${job_details}" >> "${LOG_FILE}"
                return 1
                ;;
            "processing")
                log_info "Job is processing... (${elapsed}s elapsed)"
                ;;
            *)
                log_info "Job status: ${job_status} (${elapsed}s elapsed)"
                ;;
        esac
        
        sleep ${CHECK_INTERVAL}
    done
}

# Get process_jobs function logs
get_function_logs() {
    log_info "Fetching process_jobs function logs..."
    
    # Note: This requires appropriate permissions and may need adjustment based on Supabase's logging API
    local logs=$(supabase functions logs process_jobs --limit 100 2>&1 || echo "Unable to fetch logs")
    
    echo "=== PROCESS_JOBS FUNCTION LOGS ===" >> "${LOG_FILE}"
    echo "${logs}" >> "${LOG_FILE}"
    echo "==================================" >> "${LOG_FILE}"
}

# Run comprehensive debug collection
run_debug_collection() {
    log_info "Running comprehensive debug collection..."
    
    if [[ -f "${SCRIPT_DIR}/scripts/debug-process-jobs.sh" && -n "${TEST_JOB_ID}" ]]; then
        local debug_output=$(bash "${SCRIPT_DIR}/scripts/debug-process-jobs.sh" "${TEST_JOB_ID}" 2>&1)
        echo "=== DEBUG COLLECTION OUTPUT ===" >> "${LOG_FILE}"
        echo "${debug_output}" >> "${LOG_FILE}"
        echo "===============================" >> "${LOG_FILE}"
        
        # Extract debug report filename
        local debug_file=$(echo "${debug_output}" | grep -o "debug-job-.*\.log" | head -1)
        if [[ -n "${debug_file}" && -f "${debug_file}" ]]; then
            log_info "Debug report saved to: ${debug_file}"
            cat "${debug_file}" >> "${LOG_FILE}"
        fi
    else
        log_warning "Debug script not found or no test job ID available"
    fi
}

# Rollback functions
rollback_functions() {
    log_warning "Rolling back Edge Functions to previous version..."
    
    # Use the git-based rollback script
    if [[ -f "${SCRIPT_DIR}/scripts/rollback-functions.sh" ]]; then
        log_info "Executing rollback script..."
        if bash "${SCRIPT_DIR}/scripts/rollback-functions.sh"; then
            log_success "Rollback completed successfully"
            return 0
        else
            log_error "Rollback script failed"
            return 1
        fi
    else
        log_error "Rollback script not found at ${SCRIPT_DIR}/scripts/rollback-functions.sh"
        log_info "Please manually revert the changes and re-deploy"
        return 1
    fi
}

# Clean up test data
cleanup_test_data() {
    log_info "Cleaning up test data..."
    
    if [[ -n "${TEST_JOB_ID}" ]]; then
        # Delete test job from database
        curl -s -X DELETE \
            -H "Authorization: Bearer ${SUPABASE_ANON_KEY}" \
            -H "x-client-info: ${TEST_RECEIPT_ID}" \
            "https://${SUPABASE_PROJECT_REF}.supabase.co/rest/v1/jobs?id=eq.${TEST_JOB_ID}" >> "${LOG_FILE}" 2>&1
        
        # Delete any generated audio files
        # Note: This would require additional API endpoints or direct storage access
        
        log_info "Test data cleanup completed"
    fi
}

# Main deployment flow
main() {
    log_info "=== DayStart Supabase Deployment Script ==="
    log_info "Timestamp: $(date)"
    log_info "Log file: ${LOG_FILE}"
    
    # Check environment
    log_info "Step 1/5: Checking environment variables..."
    check_env_vars
    log_success "Environment check passed"
    
    # Save current state
    log_info "Step 2/5: Saving current function versions..."
    BACKUP_FILE=$(save_function_versions)
    
    # Deploy
    log_info "Step 3/5: Deploying to Supabase..."
    if ! deploy_supabase; then
        log_error "Deployment failed!"
        exit 1
    fi
    
    # Create and monitor test job
    log_info "Step 4/5: Creating test job for validation..."
    if ! create_test_job; then
        log_error "Failed to create test job"
        get_function_logs
        run_debug_collection
        rollback_functions
        exit 1
    fi
    
    log_info "Step 5/5: Monitoring test job processing..."
    if ! monitor_job_processing; then
        log_error "Test job processing failed!"
        get_function_logs
        run_debug_collection
        log_warning "Rolling back deployment..."
        rollback_functions
        cleanup_test_data
        exit 1
    fi
    
    # Success!
    log_success "Deployment validated successfully!"
    cleanup_test_data
    
    # Clean up backup file
    [[ -f "${BACKUP_FILE}" ]] && rm -f "${BACKUP_FILE}"
    
    log_info "=== Deployment completed successfully ==="
    log_info "Full log available at: ${LOG_FILE}"
    log_success "✅ All functions deployed and tested successfully!"
}

# Run main function
main "$@"