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
- **Purpose**: GPT-4o-mini script generation, TTS audio synthesis
- **Endpoints Used**:
  - `/v1/chat/completions` (GPT-4o-mini script generation)
  - `/v1/audio/speech` (GPT-4o-mini-tts)
- **Models Used**:
  - **gpt-4o-mini**: Script generation and content adjustment
  - **gpt-4o-mini-tts**: Text-to-speech audio synthesis
- **Rate Limits** (Current Account):
  - **gpt-4o-mini**: 4,000,000 TPM, 5,000 RPM, 40,000,000 TPD
  - **gpt-4o-mini-tts**: 600,000 TPM, 5,000 RPM
- **Pricing**: Pay-per-use
  - gpt-4o-mini: ~$0.15/1M input tokens, ~$0.60/1M output tokens
  - gpt-4o-mini-tts: $15/1M characters
- **Usage Pattern**: 1-2 script generations + 1-2 TTS calls per job
- **Configuration**: `OPENAI_API_KEY` environment variable

### ElevenLabs API
- **Purpose**: Primary TTS provider using `eleven_flash_v2_5` model
- **Endpoint**: `/v1/text-to-speech/{voice_id}`
- **Voice IDs Used**:
  - `pNInz6obpgDQGcFmaJgB` (Adam)
  - `21m00Tcm4TlvDq8ikWAM` (Rachel)  
  - `AZnzlk1XvdvUeBnXmlld` (Domi)
- **Current Plan**: Creator Plan
- **Rate Limits**:
  - **Concurrency**: 5 concurrent requests
  - **Characters**: 100,000 characters/month
- **Pricing**: $0.30/1,000 characters (Creator Plan)
- **Usage Pattern**: ~500-1500 characters per job (fallback when OpenAI TTS fails)
- **Configuration**: `ELEVENLABS_API_KEY` environment variable

## News APIs

### NewsAPI
- **Purpose**: News content from multiple endpoints
- **Endpoints Used**:
  - `/v2/top-headlines` (general + business category)
  - `/v2/everything` (targeted keyword search)
- **Current Plan**: Business ($500/month)
- **Rate Limits**:
  - **Monthly Requests**: 250,000 requests/month
  - **Rate Limiting**: 1,000 requests/hour (no official concurrent limit)
- **Usage Pattern**: 
  - 3 calls per refresh cycle (general, business, targeted)
  - ~80 articles fetched per cycle
  - Refresh cycles: Every hour
  - **Monthly Usage**: ~2,160 requests/month (3 × 24 × 30)
- **Configuration**: `NEWSAPI_KEY` environment variable (optional)

### GNews API
- **Purpose**: Additional news source for content diversity
- **Endpoint**: `/v4/top-headlines`
- **Current Plan**: Essential ($60/month)
- **Rate Limits**:
  - **Daily Requests**: 1,000 requests/day
  - **Concurrent Requests**: 4 requests/second
  - **Articles per Request**: Up to 25 articles
- **Features**:
  - Real-time article availability
  - Access to all sources
  - Historical data from 2020
  - CORS enabled for all origins
  - No truncated content
  - Email support
- **Usage Pattern**: 1 call per refresh cycle (25 articles)
- **Configuration**: `GNEWS_API_KEY` environment variable (optional)

## Financial Data APIs

### Yahoo Finance (via RapidAPI)
- **Purpose**: Stock market data, forex, cryptocurrency prices
- **Endpoint**: `/market/v2/get-quotes` (apidojo-yahoo-finance-v1)
- **Current Plan**: Basic ($10/month)
- **Rate Limits**:
  - **Monthly Requests**: 10,000 requests/month
  - **Rate Limit**: 5 requests/second
- **Usage Pattern**: 
  - 1 call per refresh cycle
  - 50+ symbols per call (base symbols + user-requested)
  - Base symbols include: AAPL, GOOGL, MSFT, AMZN, TSLA, etc.
  - **Monthly Usage**: ~720 requests/month (1 × 24 × 30)
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
- **Current Plan**: Free
- **Rate Limits**: ⚠️ **Unclear/Undocumented**
  - Free tier has informal limits but no official documentation
  - Generally allows reasonable usage for small applications
  - May implement throttling during high traffic periods
- **Pricing**: Free (no cost)
- **Usage Pattern**: 1 call per refresh cycle
- **Risk Assessment**: Low priority API - graceful degradation if limits hit
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
- **Current Plan**: Pro ($25/month base)
- **Included Resources**:
  - **Monthly Active Users**: 100,000 (then $0.00325/MAU)
  - **Database Storage**: 8 GB (then $0.125/GB)
  - **Egress**: 250 GB (then $0.09/GB)
  - **Cached Egress**: 250 GB (then $0.03/GB)
  - **File Storage**: 100 GB (then $0.021/GB)
  - **Edge Functions**: 2M invocations/month
- **Features**:
  - Email support
  - Daily backups (7-day retention)
  - 7-day log retention
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
