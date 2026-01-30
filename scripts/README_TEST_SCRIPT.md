# DayStart Prompt Variety Test Script

## Purpose
Tests the new authoritative briefing prompt by creating 3 identical jobs and comparing the generated scripts for:
- Natural variety in delivery
- Elimination of filler commentary
- Authoritative tone
- Professional consistency

## Usage

```bash
cd /Users/natep/DayStart
./scripts/test_prompt_variety.sh
```

## What It Does

1. **Creates 3 test jobs** with identical settings:
   - Same location (Mar Vista, CA)
   - Same content preferences (news, sports, stocks, quotes)
   - Same duration (4 minutes)
   - Different dates (to avoid conflicts)

2. **Waits for processing** (~2-3 minutes)
   - Polls every 15 seconds
   - Shows real-time status updates

3. **Displays all 3 scripts** side-by-side for comparison

## What to Look For

### ✅ GOOD SIGNS (What we want)
- **Varied sentence structure**: Script 1 vs 2 vs 3 should feel different
- **Different section openers**: "Weather update" vs "Quick weather check" vs "Here's your weather"
- **Direct facts**: "Mar Vista hits 82 today" (not "Mar Vista will be feeling summery")
- **Confident delivery**: "Your calendar's packed" (not "you might want to consider")
- **Authoritative sign-offs**: "Go make Monday count" (not "Peel into this Monday with intention")

### ❌ RED FLAGS (What we eliminated)
- "which means you'll want to..."
- "we all know how..."
- Cute jokes or performative commentary
- "downright summery" or overly folksy language
- Explaining obvious implications
- "your teeth are going to file for separation"
- "traffic is allergic to being on time"

## Test Configuration

Edit these variables in the script to customize:

```bash
TIMEZONE="America/Los_Angeles"
PREFERRED_NAME="Jordan"
DAYSTART_LENGTH=240  # 4 minutes
```

## Output

The script will display:
1. Job creation confirmation
2. Processing status updates
3. All 3 generated scripts in full
4. Analysis tips

## Cleanup

Test jobs use unique user IDs like `test_prompt_variety_1738368000_job1` and won't interfere with real users.

## Troubleshooting

**Jobs stuck in 'queued'?**
- Check if `process_jobs` cron is running
- May need to manually trigger job processing

**Jobs failed?**
- Check Supabase logs for errors
- Verify content cache has recent data

**Can't retrieve scripts?**
- Jobs may still be processing
- Increase MAX_WAIT timeout in script
