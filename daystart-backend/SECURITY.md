# DayStart Backend Security Architecture

## Security Principles

### 1. **Principle of Least Privilege**
- Users can only access their own data
- Anonymous users have no database access
- Service role has full access only for backend operations
- Edge Functions act as secure API gateway

### 2. **Defense in Depth**
- Multiple layers of security (RLS + Edge Functions + Input validation)
- Client-side cannot bypass server-side security
- All sensitive operations require service role authentication

### 3. **Zero Trust Architecture**
- Every request is validated and authenticated
- No implicit trust between components
- All data access is explicitly controlled

## Row Level Security (RLS) Policies

### User Schedule Table
```sql
-- Users can only access their own schedule
auth.uid() = user_id  -- For all user operations

-- Service role has full access for backend sync
true  -- For service_role only
```

### Jobs Table  
```sql
-- Users can VIEW their own jobs only
auth.uid() = user_id  -- SELECT only

-- Users CANNOT directly modify jobs
false  -- For INSERT/UPDATE/DELETE by users

-- All job modifications must go through Edge Functions
true  -- For service_role only
```

### Content Blocks Table
```sql
-- Users have NO direct access
false  -- For all user operations

-- Only backend can manage shared content
true  -- For service_role only
```

### Quote History Table
```sql  
-- Users can view their own quotes (read-only)
auth.uid() = user_id  -- SELECT only

-- Cannot modify quote history directly
false  -- For INSERT/UPDATE/DELETE by users
```

### Logs Table
```sql
-- Users have NO access to system logs
false  -- For all user operations

-- Only backend can write logs
true  -- For service_role only
```

### Storage Objects
```sql
-- Users cannot directly access storage
false  -- For all user operations

-- Only backend can manage audio files
bucket_id = 'audio-files' AND role = 'service_role'
```

## Edge Function Security

### Authentication Flow
1. **Client Authentication**: iOS app uses Supabase Auth (JWT)
2. **Service Authentication**: Edge Functions use service_role key
3. **Request Validation**: All inputs validated before processing
4. **Authorization Check**: User ownership verified for all operations

### Secure Database Operations
All database operations use security-definer functions:

#### `create_user_job()`
- Validates user exists in auth.users
- Enforces business rules (time windows, length limits)
- Uses UPSERT pattern for idempotency
- Logs all operations with privacy-safe user hashes

#### `lease_jobs_for_processing()`  
- Implements FOR UPDATE SKIP LOCKED pattern
- Prevents race conditions between workers
- Enforces lease timeouts
- Limits job processing window (next 6 hours only)

#### `complete_job_step()`
- Validates worker owns the lease
- Enforces valid status transitions
- Releases locks properly
- Comprehensive operation logging

#### `safe_log()`
- Privacy-safe logging with user ID hashing
- Structured metadata for observability
- Input validation and sanitization

## API Security

### Endpoint Authentication
- **User Endpoints**: Require valid JWT from Supabase Auth
- **Cron Endpoints**: Require service_role key + custom secret
- **Worker Endpoints**: Require service_role key only

### Input Validation
- **Type Safety**: All inputs validated against expected types
- **Business Rules**: Time windows, length limits, enum values
- **Injection Protection**: Parameterized queries only
- **Size Limits**: File size, text length, array size limits

### Rate Limiting
- **User API**: Limited by Supabase (configurable)
- **Worker APIs**: Internal only, no external access
- **Cron APIs**: Called by authorized cron service only

## Storage Security

### Audio Files Bucket
- **Private Bucket**: No public access
- **Signed URLs**: 30-minute expiration maximum
- **MIME Type Restrictions**: Only audio formats allowed
- **Size Limits**: 50MB maximum per file
- **Path Structure**: Organized by date/user for access control

### File Access Pattern
1. User requests audio through Edge Function
2. Edge Function validates user owns the job
3. Generate signed URL with short expiration
4. Return signed URL to authenticated user only
5. User downloads directly from storage with signed URL

## Privacy Protection

### User Data Handling
- **User IDs**: Hashed in logs using SHA-256
- **Personal Data**: Encrypted at rest by Supabase
- **Location Data**: Stored as JSONB, not indexed for privacy
- **Audio Content**: Deleted after 7 days automatically

### Data Retention
- **User Data**: Retained until user deletes account
- **Audio Files**: 7-day automatic deletion
- **Logs**: Retained indefinitely for system monitoring
- **Jobs**: Retained for analytics (no personal content)

### GDPR Compliance
- **Right to Access**: Users can view their own data
- **Right to Deletion**: CASCADE deletes implemented
- **Right to Portability**: JSON export available
- **Data Minimization**: Only necessary data collected

## Threat Mitigation

### SQL Injection
- **Prevention**: Parameterized queries only
- **Detection**: Input validation and sanitization
- **Response**: Query execution monitoring

### Unauthorized Access
- **Prevention**: Comprehensive RLS policies
- **Detection**: Access attempt logging
- **Response**: Automatic blocking and alerting

### Data Leakage
- **Prevention**: Private storage with signed URLs
- **Detection**: Unusual access pattern monitoring  
- **Response**: Immediate access revocation

### API Abuse
- **Prevention**: Rate limiting and input validation
- **Detection**: Unusual request pattern monitoring
- **Response**: IP blocking and alerting

### Worker Security
- **Prevention**: Lease-based job processing
- **Detection**: Worker health monitoring
- **Response**: Automatic failover and alerting

## Security Monitoring

### Audit Logging
- **User Actions**: All user operations logged
- **System Events**: Worker operations, errors, performance
- **Security Events**: Authentication failures, suspicious activity
- **Privacy**: User IDs hashed, no sensitive data in logs

### Health Monitoring
- **Database Performance**: Query performance monitoring
- **API Response Times**: Edge Function performance tracking
- **Error Rates**: Failure rate monitoring and alerting
- **Security Metrics**: Authentication success/failure rates

### Incident Response
- **Detection**: Automated monitoring and alerting
- **Response**: Automated containment and manual investigation
- **Recovery**: Backup restoration and system hardening
- **Learning**: Post-incident analysis and improvements

## Security Testing

### Penetration Testing Checklist
- [ ] RLS policy bypass attempts
- [ ] JWT token manipulation
- [ ] SQL injection testing
- [ ] Unauthorized file access attempts
- [ ] Rate limiting validation
- [ ] Input validation bypass attempts

### Security Review Process
- [ ] Code review for security issues
- [ ] RLS policy verification
- [ ] Edge Function security validation
- [ ] Storage access control verification
- [ ] API endpoint security testing
- [ ] Documentation security review

## Security Configuration

### Supabase Settings
```toml
# Enforce secure configurations
[auth]
enable_signup = true  # Controlled signup
jwt_expiry = 3600     # 1 hour token expiration
enable_refresh_token_rotation = true

[storage]
file_size_limit = "50MiB"  # Reasonable file size limit
```

### Environment Variables
All secrets must be:
- Stored in GitHub Secrets (never committed)
- Rotated regularly (quarterly minimum)  
- Scoped to minimum required permissions
- Monitored for unauthorized access

This security architecture ensures that user data is protected at every level while maintaining the performance and functionality required for the DayStart application.