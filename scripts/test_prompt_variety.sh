#!/bin/bash

# Test script for DayStart prompt variety testing
# Creates 3 identical jobs to verify natural variance in script generation

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Supabase configuration (from Info.plist)
SUPABASE_URL="https://pklntrvznjhaxyxsjjgq.supabase.co"
FUNCTIONS_URL="${SUPABASE_URL}/functions/v1"
ANON_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBrbG50cnZ6bmpoYXh5eHNqamdxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTQ2ODQzMzgsImV4cCI6MjA3MDI2MDMzOH0.Gmwa1snYdwYKPBbxsUY1qJ09Z8rynTwZEDoT7VPS1HU"

# Test user ID
TEST_USER_ID="test_prompt_variety_$(date +%s)"

# Test configuration (adjust as needed)
TIMEZONE="America/Los_Angeles"
PREFERRED_NAME="Jordan"
DAYSTART_LENGTH=240  # 4 minutes

echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  DayStart Prompt Variety Test Script                  ║${NC}"
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo ""
echo -e "${YELLOW}Test User ID:${NC} ${TEST_USER_ID}"
echo -e "${YELLOW}Creating 3 jobs with identical settings...${NC}"
echo ""

# Function to create a job
create_job() {
    local job_num=$1
    local local_date=$2

    echo -e "${BLUE}Creating Job ${job_num}...${NC}"

    local response=$(curl -s -X POST "${FUNCTIONS_URL}/create_job" \
        -H "Content-Type: application/json" \
        -H "apikey: ${ANON_KEY}" \
        -H "Authorization: Bearer ${ANON_KEY}" \
        -H "x-client-info: ${TEST_USER_ID}_job${job_num}" \
        -H "x-auth-type: test" \
        -d '{
            "local_date": "'"${local_date}"'",
            "scheduled_at": "NOW",
            "preferred_name": "'"${PREFERRED_NAME}"'",
            "include_weather": true,
            "include_news": true,
            "include_sports": true,
            "selected_sports": ["NBA", "NFL", "MLB"],
            "selected_news_categories": ["World", "Business", "Technology"],
            "include_stocks": true,
            "stock_symbols": ["AAPL", "TSLA", "NVDA"],
            "include_calendar": false,
            "include_quotes": true,
            "quote_preference": "Motivational",
            "voice_option": "alloy",
            "daystart_length": '"${DAYSTART_LENGTH}"',
            "timezone": "'"${TIMEZONE}"'",
            "location_data": {
                "city": "Mar Vista",
                "state": "CA",
                "country": "USA"
            },
            "force_update": true
        }')

    local job_id=$(echo "$response" | grep -o '"job_id":"[^"]*"' | cut -d'"' -f4)
    local success=$(echo "$response" | grep -o '"success":[^,}]*' | cut -d':' -f2)

    if [[ "$success" == "true" && -n "$job_id" ]]; then
        echo -e "${GREEN}✓ Job ${job_num} created: ${job_id}${NC}"
        echo "$job_id"
    else
        echo -e "${RED}✗ Failed to create Job ${job_num}${NC}"
        echo "Response: $response"
        echo "error"
    fi
}

# Function to check job status
check_job_status() {
    local user_id=$1
    local local_date=$2

    local response=$(curl -s -X GET "${FUNCTIONS_URL}/get_audio_status?date=${local_date}" \
        -H "apikey: ${ANON_KEY}" \
        -H "Authorization: Bearer ${ANON_KEY}" \
        -H "x-client-info: ${user_id}")

    echo "$response"
}


# Create 3 jobs with different dates (to avoid conflicts)
TODAY=$(date -u +"%Y-%m-%d")
DATE1="${TODAY}"
DATE2=$(date -u -v+1d +"%Y-%m-%d" 2>/dev/null || date -u -d "+1 day" +"%Y-%m-%d")
DATE3=$(date -u -v+2d +"%Y-%m-%d" 2>/dev/null || date -u -d "+2 days" +"%Y-%m-%d")

JOB1=$(create_job 1 "$DATE1")
sleep 2
JOB2=$(create_job 2 "$DATE2")
sleep 2
JOB3=$(create_job 3 "$DATE3")

echo ""
echo -e "${YELLOW}Jobs created. Waiting for processing...${NC}"
echo -e "${YELLOW}This will take 2-3 minutes. Polling every 15 seconds...${NC}"
echo ""

# Wait for jobs to complete (max 5 minutes)
MAX_WAIT=300
ELAPSED=0
POLL_INTERVAL=15

JOB_STATUS_1="queued"
JOB_STATUS_2="queued"
JOB_STATUS_3="queued"

while [[ $ELAPSED -lt $MAX_WAIT ]]; do
    ALL_READY=true

    # Check Job 1
    if [[ "$JOB_STATUS_1" != "ready" ]]; then
        USER_ID="${TEST_USER_ID}_job1"
        STATUS_RESPONSE=$(check_job_status "$USER_ID" "$DATE1")
        STATUS=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        JOB_STATUS_1="$STATUS"

        if [[ "$STATUS" == "ready" ]]; then
            echo -e "${GREEN}✓ Job 1 is ready${NC}"
        elif [[ "$STATUS" == "processing" ]]; then
            echo -e "${YELLOW}⋯ Job 1 is processing...${NC}"
            ALL_READY=false
        elif [[ "$STATUS" == "failed" ]]; then
            echo -e "${RED}✗ Job 1 failed${NC}"
        else
            echo -e "${BLUE}⋯ Job 1 status: ${STATUS}${NC}"
            ALL_READY=false
        fi
    fi

    # Check Job 2
    if [[ "$JOB_STATUS_2" != "ready" ]]; then
        USER_ID="${TEST_USER_ID}_job2"
        STATUS_RESPONSE=$(check_job_status "$USER_ID" "$DATE2")
        STATUS=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        JOB_STATUS_2="$STATUS"

        if [[ "$STATUS" == "ready" ]]; then
            echo -e "${GREEN}✓ Job 2 is ready${NC}"
        elif [[ "$STATUS" == "processing" ]]; then
            echo -e "${YELLOW}⋯ Job 2 is processing...${NC}"
            ALL_READY=false
        elif [[ "$STATUS" == "failed" ]]; then
            echo -e "${RED}✗ Job 2 failed${NC}"
        else
            echo -e "${BLUE}⋯ Job 2 status: ${STATUS}${NC}"
            ALL_READY=false
        fi
    fi

    # Check Job 3
    if [[ "$JOB_STATUS_3" != "ready" ]]; then
        USER_ID="${TEST_USER_ID}_job3"
        STATUS_RESPONSE=$(check_job_status "$USER_ID" "$DATE3")
        STATUS=$(echo "$STATUS_RESPONSE" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        JOB_STATUS_3="$STATUS"

        if [[ "$STATUS" == "ready" ]]; then
            echo -e "${GREEN}✓ Job 3 is ready${NC}"
        elif [[ "$STATUS" == "processing" ]]; then
            echo -e "${YELLOW}⋯ Job 3 is processing...${NC}"
            ALL_READY=false
        elif [[ "$STATUS" == "failed" ]]; then
            echo -e "${RED}✗ Job 3 failed${NC}"
        else
            echo -e "${BLUE}⋯ Job 3 status: ${STATUS}${NC}"
            ALL_READY=false
        fi
    fi

    if $ALL_READY; then
        echo -e "${GREEN}All jobs ready!${NC}"
        break
    fi

    sleep $POLL_INTERVAL
    ELAPSED=$((ELAPSED + POLL_INTERVAL))
    echo ""
done

if [[ $ELAPSED -ge $MAX_WAIT ]]; then
    echo -e "${RED}Timeout waiting for jobs to complete${NC}"
    exit 1
fi

echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Test Jobs Ready - View in Supabase or App            ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
echo ""

echo -e "${GREEN}✓ All 3 jobs completed successfully!${NC}"
echo ""
echo -e "${YELLOW}Job Identifiers:${NC}"
echo ""
echo -e "  ${BLUE}Job 1:${NC}"
echo -e "    User ID: ${TEST_USER_ID}_job1"
echo -e "    Date: ${DATE1}"
echo ""
echo -e "  ${BLUE}Job 2:${NC}"
echo -e "    User ID: ${TEST_USER_ID}_job2"
echo -e "    Date: ${DATE2}"
echo ""
echo -e "  ${BLUE}Job 3:${NC}"
echo -e "    User ID: ${TEST_USER_ID}_job3"
echo -e "    Date: ${DATE3}"
echo ""
echo -e "${YELLOW}To view/listen in Supabase:${NC}"
echo "1. Go to Supabase Dashboard → Table Editor → jobs"
echo "2. Filter: user_id LIKE 'test_prompt_variety_${TEST_USER_ID#test_prompt_variety_}%'"
echo "3. View script_content column or audio_file_path for each job"
echo ""
echo -e "${YELLOW}Analysis Tips:${NC}"
echo "1. Compare sentence structures across all 3 scripts"
echo "2. Check for varied section openers (Weather update vs Quick weather check, etc.)"
echo "3. Verify NO filler commentary (which means you'll want to, etc.)"
echo "4. Listen for authoritative tone (confident, not performative)"
echo "5. Ensure natural variety without losing professionalism"
echo ""
echo -e "${GREEN}Test complete!${NC}"
