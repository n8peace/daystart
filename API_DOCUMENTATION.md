# API Documentation & Rate Limits

This document provides a comprehensive overview of all external APIs used in the DayStart application, including rate limits, pricing, and usage patterns.

## Table of Contents
- [AI & Text-to-Speech APIs](#ai--text-to-speech-apis)
- [News APIs](#news-apis)
- [Financial Data APIs](#financial-data-apis)
- [Sports APIs](#sports-apis)
- [Weather APIs](#weather-apis)
- [Backend & Infrastructure](#backend--infrastructure)
- [Monitoring & Rate Limit Management](#monitoring--rate-limit-management)
- [Cost Optimization Strategies](#cost-optimization-strategies)

## AI & Text-to-Speech APIs

### OpenAI API
- **Purpose**: GPT-4 script generation, TTS audio synthesis
- **Endpoints Used**:
  - `/v1/chat/completions` (GPT-4 script generation)
  - `/v1/audio/speech` (text-to-speech)
- **Rate Limits**:
  - **GPT-4**: 10,000 requests/minute (Tier 1), 90,000 requests/minute (Tier 5)
  - **TTS**: 50 requests/minute
- **Pricing**: Pay-per-use
  - GPT-4: ~$30/1M input tokens, ~$60/1M output tokens
  - TTS: $15/1M characters
- **Usage Pattern**: 1-2 script generations + 1-2 TTS calls per job
- **Configuration**: `OPENAI_API_KEY` environment variable

### ElevenLabs API
- **Purpose**: Primary TTS provider using `eleven_flash_v2_5` model
- **Endpoint**: `/v1/text-to-speech/{voice_id}`
- **Voice IDs Used**:
  - `pNInz6obpgDQGcFmaJgB` (Adam)
  - `21m00Tcm4TlvDq8ikWAM` (Rachel)  
  - `AZnzlk1XvdvUeBnXmlld` (Domi)
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your current plan
  - Free: 10,000 characters/month
  - Starter: 30,000 characters/month
  - Creator: 100,000 characters/month
  - Pro: 500,000 characters/month
- **Pricing**: Character-based
  - Free: $0 (10K chars)
  - Starter: $5/month (30K chars)
  - Creator: $22/month (100K chars)
  - Pro: $99/month (500K chars)
- **Usage Pattern**: ~500-1500 characters per job (fallback when OpenAI TTS fails)
- **Configuration**: `ELEVENLABS_API_KEY` environment variable

## News APIs

### NewsAPI
- **Purpose**: News content from multiple endpoints
- **Endpoints Used**:
  - `/v2/top-headlines` (general + business category)
  - `/v2/everything` (targeted keyword search)
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your current plan
  - Developer (Free): 1,000 requests/month
  - Business: 250,000 requests/month
- **Pricing**:
  - Developer: Free (1K requests/month)
  - Business: $449/month (250K requests/month)
- **Usage Pattern**: 
  - 3 calls per refresh cycle (general, business, targeted)
  - ~80 articles fetched per cycle
  - Refresh cycles: Every hour
- **Configuration**: `NEWSAPI_KEY` environment variable (optional)

### GNews API
- **Purpose**: Additional news source for content diversity
- **Endpoint**: `/v4/top-headlines`
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your current plan
  - Free: 100 requests/day
  - Basic: 10,000 requests/month
  - Professional: 100,000 requests/month
- **Pricing**:
  - Free: $0 (100 requests/day)
  - Basic: $9/month (10K requests/month)
  - Professional: $99/month (100K requests/month)
- **Usage Pattern**: 1 call per refresh cycle (25 articles)
- **Configuration**: `GNEWS_API_KEY` environment variable (optional)

## Financial Data APIs

### Yahoo Finance (via RapidAPI)
- **Purpose**: Stock market data, forex, cryptocurrency prices
- **Endpoint**: `/market/v2/get-quotes` (apidojo-yahoo-finance-v1)
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your RapidAPI plan
  - Free: 500 requests/month
  - Basic: 10,000 requests/month
  - Pro: 100,000 requests/month
- **Pricing**:
  - Free: $0 (500 requests/month)
  - Basic: $10/month (10K requests/month)
  - Pro: $100/month (100K requests/month)
- **Usage Pattern**: 
  - 1 call per refresh cycle
  - 50+ symbols per call (base symbols + user-requested)
  - Base symbols include: AAPL, GOOGL, MSFT, AMZN, TSLA, etc.
- **Configuration**: `RAPIDAPI_KEY` environment variable (optional)

## Sports APIs

### ESPN API
- **Purpose**: NBA scores and sports data
- **Endpoint**: `https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard`
- **Rate Limits**: ✅ **Public API** - No authentication required
- **Pricing**: Free
- **Usage Pattern**: 1 call per refresh cycle
- **Configuration**: None required

### TheSportDB API
- **Purpose**: Additional sports data and scores
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your current plan
  - Free: 10 requests/hour per IP
  - Patreon Supporter: Higher limits
- **Pricing**:
  - Free: $0 (10 requests/hour)
  - Patreon: $2+/month (higher limits)
- **Usage Pattern**: 1 call per refresh cycle
- **Configuration**: None required for free tier

## Weather APIs

### Apple WeatherKit
- **Purpose**: Local weather data and forecasts
- **Integration**: Native iOS CoreLocation + WeatherKit
- **Rate Limits**: ✅ **500,000 calls/month free**, then $0.50/1K calls
- **Pricing**: 
  - Free: 500,000 calls/month
  - Paid: $0.50 per 1,000 calls above free tier
- **Usage Pattern**: 1-2 calls per job (current + forecast)
- **Configuration**: Apple Developer Program membership required

## Backend & Infrastructure

### Supabase
- **Purpose**: Database, functions, storage, authentication
- **Services Used**:
  - PostgreSQL database
  - Edge functions
  - Storage buckets
  - Real-time subscriptions
- **Rate Limits**: ⚠️ **PLAN DEPENDENT** - Please specify your current plan
  - Free: 500MB database, 2GB bandwidth, 500K edge function invocations
  - Pro: 8GB database, 50GB bandwidth, 2M edge function invocations
- **Pricing**:
  - Free: $0 (with limits)
  - Pro: $25/month + usage
- **Usage Pattern**: Continuous usage for all app operations
- **Configuration**: Multiple environment variables in iOS app

### Cron-job.org
- **Purpose**: Scheduled content refresh triggers
- **Rate Limits**: ✅ **Free tier supports basic cron jobs**
- **Pricing**: Free for basic usage
- **Usage Pattern**: Hourly triggers for content refresh
- **Configuration**: Web-based cron job setup

## Monitoring & Rate Limit Management

### Current Rate Limiting Strategy
1. **API Key Validation**: All APIs check for required keys before making calls
2. **Graceful Degradation**: Missing APIs are logged but don't break the system
3. **Content Caching**: 168-hour TTL reduces API calls
4. **Request Bundling**: Multiple data points per API call when possible

### Usage Tracking
- **Cost Tracking**: OpenAI and ElevenLabs usage logged in database
- **Request Logging**: All API calls logged with timestamps
- **Error Monitoring**: Failed API calls tracked for rate limit detection

### Rate Limit Handling
```typescript
// Example from refresh_content function
const missingEnvs: string[] = []
if (Deno.env.get('NEWSAPI_KEY')) {
  // Include NewsAPI sources
} else { 
  missingEnvs.push('NEWSAPI_KEY') 
}
```

## Cost Optimization Strategies

### Current Optimizations
1. **Content Caching**: 7-day cache reduces API calls by ~95%
2. **Conditional API Usage**: Only enabled APIs are called
3. **Batch Processing**: Multiple symbols per Yahoo Finance call
4. **Fallback Providers**: ElevenLabs as TTS fallback to OpenAI

### Recommended Monitoring
1. **Set up billing alerts** for all paid APIs
2. **Monitor monthly usage** against plan limits
3. **Track cost per user** for scaling projections
4. **Implement circuit breakers** for expensive APIs

## Action Items

⚠️ **MISSING INFORMATION NEEDED**:

Please provide the following plan details to complete this documentation:

1. **ElevenLabs Plan**: Free/Starter/Creator/Pro?
2. **NewsAPI Plan**: Developer (Free)/Business?
3. **GNews Plan**: Free/Basic/Professional?
4. **RapidAPI Plan**: Free/Basic/Pro?
5. **TheSportDB Plan**: Free/Patreon?
6. **Supabase Plan**: Free/Pro?

Once provided, this document will be updated with exact rate limits and monthly costs.

---

**Last Updated**: January 2025  
**Maintained By**: Development Team  
**Review Schedule**: Monthly or when API plans change
