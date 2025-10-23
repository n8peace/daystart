# Segmented Welcome DayStart Implementation Plan

## 🎯 Objective
Implement "instant" welcome DayStarts by splitting audio generation into 3-5 segments, allowing the first segment to play within 10-15 seconds while remaining segments generate in the background.

## 🚨 Production Constraints
- **BACKWARDS COMPATIBILITY MANDATORY**: Current app versions must continue to work
- **Feature Flag Gated**: Only enable for supported app versions + welcome DayStarts
- **Rollback Strategy**: Fallback to single-file generation if segmented fails
- **Zero Breaking Changes**: Existing API contracts must remain intact

## 📋 Current State Analysis

### Existing Welcome DayStart Flow
1. User completes onboarding → `scheduleWelcomeDayStart()` called
2. Job created with `is_welcome: true`, 60-second length
3. `process_jobs` generates single script → single TTS → single audio file
4. iOS polls `get_audio_status` every 10 seconds until `status: "ready"`
5. Audio downloaded and played as single file

### Performance Issues
- Full generation takes 45-90 seconds (script + TTS)
- User waits entire duration before any audio plays
- No progressive experience or perceived performance

## 🏗️ Segmented Architecture Design

### Segment Structure (5 segments, ~60 seconds total)
1. **Greeting & Introduction** (12s): "Good morning [name], welcome to DayStart..."
2. **Weather & Location** (12s): Current weather and location-based info  
3. **Calendar Preview** (12s): Today's upcoming events if available
4. **News Highlights** (12s): Top 2-3 curated news stories
5. **Motivational Close** (12s): Daily quote and encouraging sign-off

### Feature Flag Conditions
```typescript
Enable segmented audio when ALL conditions met:
- job.is_welcome === true
- app_version >= "2025.10.23" (version detection from User-Agent)
- job.use_segmented_audio === true (set during job creation)
```

## 🗄️ Database Schema Changes

### Jobs Table Additions
```sql
-- Add to existing jobs table
ALTER TABLE jobs ADD COLUMN use_segmented_audio BOOLEAN DEFAULT false;
ALTER TABLE jobs ADD COLUMN segment_count INTEGER DEFAULT 1;
ALTER TABLE jobs ADD COLUMN segments_ready INTEGER DEFAULT 0;
ALTER TABLE jobs ADD COLUMN segment_status JSONB DEFAULT '{}';
```

### New Audio Segments Table
```sql
CREATE TABLE audio_segments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  job_id UUID NOT NULL REFERENCES jobs(job_id) ON DELETE CASCADE,
  segment_index INTEGER NOT NULL,
  audio_file_path TEXT,
  duration_seconds NUMERIC(5,2),
  script_content TEXT,
  status TEXT DEFAULT 'queued', -- queued, processing, ready, failed
  tts_cost NUMERIC(10,6),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,
  
  UNIQUE(job_id, segment_index),
  INDEX(job_id, segment_index),
  INDEX(status)
);
```

## 🔧 Backend Implementation

### 1. Version Detection in create_job
```typescript
// In create_job/index.ts
function detectAppVersion(userAgent: string): string {
  // Parse User-Agent: "DayStart/2025.10.23 CFNetwork/..."
  const match = userAgent.match(/DayStart\/(\d{4}\.\d{2}\.\d{2})/);
  return match?.[1] || '2025.01.01'; // fallback to old version
}

function supportsSegmentedAudio(version: string): boolean {
  return version >= '2025.10.23';
}

// Set segmented flag during job creation
const appVersion = detectAppVersion(req.headers.get('user-agent') || '');
const useSegmented = body.is_welcome && supportsSegmentedAudio(appVersion);

const jobData = {
  // ... existing fields
  use_segmented_audio: useSegmented,
  segment_count: useSegmented ? 5 : 1,
  segment_status: useSegmented ? {1: 'queued', 2: 'queued', 3: 'queued', 4: 'queued', 5: 'queued'} : {}
};
```

### 2. Segmented Script Generation
```typescript
// In process_jobs/index.ts
async function generateSegmentedScript(job: any, contentData: any): Promise<SegmentScript[]> {
  const segments = [
    generateGreetingSegment(job, contentData),
    generateWeatherSegment(job, contentData), 
    generateCalendarSegment(job, contentData),
    generateNewsSegment(job, contentData),
    generateMotivationalSegment(job, contentData)
  ];
  
  return Promise.all(segments);
}

async function generateGreetingSegment(job: any, contentData: any): Promise<SegmentScript> {
  const prompt = `Create a warm 12-second welcome greeting for ${job.preferred_name || 'there'}.
  This is their first DayStart experience. Be enthusiastic but natural.
  Include: Welcome to DayStart, brief explanation of what's coming.
  Target: ~35 words, natural speaking pace.`;
  
  const content = await callOpenAI(prompt, { maxTokens: 80 });
  return {
    index: 1,
    content,
    targetDuration: 12,
    wordCount: content.split(' ').length
  };
}
```

### 3. Parallel TTS Generation
```typescript
async function processSegmentedJob(job: any): Promise<void> {
  const segments = await generateSegmentedScript(job, contentData);
  
  // Generate all segments in parallel for speed
  const audioPromises = segments.map(segment => 
    generateSegmentAudio(job, segment)
  );
  
  const audioResults = await Promise.allSettled(audioPromises);
  
  // Update job status as segments complete
  for (let i = 0; i < audioResults.length; i++) {
    if (audioResults[i].status === 'fulfilled') {
      await updateSegmentStatus(job.job_id, i + 1, 'ready');
    }
  }
  
  // Generate fallback single file for backwards compatibility
  await generateFallbackAudio(job, segments);
}

async function generateSegmentAudio(job: any, segment: SegmentScript): Promise<AudioResult> {
  const audioResult = await generateAudio(segment.content, job);
  
  if (audioResult.success) {
    // Store segment audio file
    const filePath = `${job.job_id}_segment_${segment.index}.aac`;
    await uploadToSupabaseStorage(audioResult.audioData, filePath);
    
    // Save to audio_segments table
    await supabase.from('audio_segments').insert({
      job_id: job.job_id,
      segment_index: segment.index,
      audio_file_path: filePath,
      duration_seconds: audioResult.duration,
      script_content: segment.content,
      status: 'ready',
      tts_cost: audioResult.cost
    });
  }
  
  return audioResult;
}
```

### 4. Updated get_audio_status API
```typescript
// Enhanced response for segmented jobs
interface AudioStatusResponse {
  success: boolean;
  status: 'queued' | 'processing' | 'ready' | 'failed';
  jobId?: string;
  // New segmented fields
  is_segmented?: boolean;
  segment_count?: number;
  segments_ready?: number;
  segment_status?: Record<number, 'queued' | 'processing' | 'ready' | 'failed'>;
  // Backwards compatibility
  audio_url?: string; // Single file URL for non-segmented
}

// In get_audio_status/index.ts
if (job.use_segmented_audio) {
  const segments = await supabase
    .from('audio_segments')
    .select('segment_index, status')
    .eq('job_id', job.job_id)
    .order('segment_index');
    
  const segmentStatus = segments.reduce((acc, seg) => {
    acc[seg.segment_index] = seg.status;
    return acc;
  }, {});
  
  const segmentsReady = segments.filter(s => s.status === 'ready').length;
  const overallStatus = segmentsReady > 0 ? 'ready' : 'processing';
  
  return {
    success: true,
    status: overallStatus,
    is_segmented: true,
    segment_count: job.segment_count,
    segments_ready: segmentsReady,
    segment_status: segmentStatus,
    // Fallback single file for backwards compatibility
    audio_url: job.audio_file_path
  };
}
```

### 5. New get_audio_segment Endpoint
```typescript
// New endpoint: supabase/functions/get_audio_segment/index.ts
serve(async (req: Request) => {
  const url = new URL(req.url);
  const jobId = url.searchParams.get('job_id');
  const segmentIndex = parseInt(url.searchParams.get('segment_index') || '1');
  
  const segment = await supabase
    .from('audio_segments')
    .select('audio_file_path, status')
    .eq('job_id', jobId)
    .eq('segment_index', segmentIndex)
    .single();
    
  if (segment.status !== 'ready') {
    return Response.json({ 
      success: false, 
      error: 'Segment not ready',
      status: segment.status 
    });
  }
  
  // Return pre-signed URL or direct audio stream
  const audioUrl = await getSupabaseStorageUrl(segment.audio_file_path);
  return Response.json({ success: true, audio_url: audioUrl });
});
```

## 📱 iOS Implementation Changes

### 1. Detection & Feature Flag
```swift
// In HomeViewModel.swift
private func supportsSegmentedAudio() -> Bool {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2025.01.01"
    return appVersion >= "2025.10.23"
}

private func shouldUseSegmentedPlayer(for audioStatus: AudioStatus) -> Bool {
    return audioStatus.isSegmented == true && supportsSegmentedAudio()
}
```

### 2. Segmented Audio Player
```swift
// New class: SegmentedAudioPlayer.swift
class SegmentedAudioPlayer: ObservableObject {
    @Published var isPlaying = false
    @Published var currentSegment = 1
    @Published var totalDuration: TimeInterval = 0
    
    private var segmentPlayers: [AVAudioPlayer] = []
    private var segmentQueue: [URL] = []
    private var jobId: String?
    
    func loadSegmentedAudio(jobId: String, segmentCount: Int) {
        self.jobId = jobId
        
        // Load first segment immediately
        loadSegment(index: 1) { [weak self] success in
            if success {
                self?.playCurrentSegment()
                // Preload remaining segments in background
                self?.preloadRemainingSegments(count: segmentCount)
            }
        }
    }
    
    private func loadSegment(index: Int, completion: @escaping (Bool) -> Void) {
        guard let jobId = jobId else { return }
        
        Task {
            do {
                let segmentData = try await SupabaseClient.shared.getAudioSegment(
                    jobId: jobId, 
                    segmentIndex: index
                )
                
                let audioPlayer = try AVAudioPlayer(data: segmentData)
                audioPlayer.delegate = self
                
                await MainActor.run {
                    self.segmentPlayers.append(audioPlayer)
                    completion(true)
                }
            } catch {
                await MainActor.run {
                    completion(false)
                }
            }
        }
    }
    
    private func playCurrentSegment() {
        guard currentSegment <= segmentPlayers.count else { return }
        
        let player = segmentPlayers[currentSegment - 1]
        player.play()
        isPlaying = true
    }
}

// AVAudioPlayerDelegate for seamless transitions
extension SegmentedAudioPlayer: AVAudioPlayerDelegate {
    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        currentSegment += 1
        
        if currentSegment <= segmentPlayers.count {
            playCurrentSegment()
        } else {
            isPlaying = false
            // All segments complete
        }
    }
}
```

### 3. Updated HomeViewModel Integration
```swift
// In HomeViewModel.swift
@Published var segmentedPlayer = SegmentedAudioPlayer()
@Published var useSegmentedPlayback = false

private func handleAudioStatusResponse(_ response: AudioStatusResponse) {
    if response.isSegmented == true && supportsSegmentedAudio() {
        useSegmentedPlayback = true
        
        if response.segmentsReady > 0 {
            segmentedPlayer.loadSegmentedAudio(
                jobId: response.jobId,
                segmentCount: response.segmentCount
            )
        }
    } else {
        // Use existing single-file audio player
        useSegmentedPlayback = false
        // Handle traditional audio playback
    }
}
```

## 🔄 Backwards Compatibility Strategy

### API Compatibility
- `get_audio_status` returns both segmented data AND traditional `audio_url` field
- Existing apps ignore segmented fields, use `audio_url` as before
- New apps detect `is_segmented: true` and use segment APIs

### Fallback Mechanisms
1. **Segment Generation Failure**: Fall back to single-file generation
2. **Version Detection Failure**: Default to single-file mode
3. **iOS Segmented Player Failure**: Fall back to traditional player

### Database Migrations
```sql
-- All columns are additive with sensible defaults
-- No existing data is modified
-- RLS policies automatically apply to new table
```

## 🧪 Testing Strategy

### Backend Testing
- [ ] Unit tests for version detection logic
- [ ] Integration tests for segmented script generation
- [ ] Parallel TTS generation stress tests
- [ ] Backwards compatibility verification
- [ ] Segment failure scenarios

### iOS Testing
- [ ] Segmented audio playback with network delays
- [ ] Segment loading failure handling
- [ ] Traditional audio fallback verification
- [ ] Battery/performance impact testing
- [ ] Background playback with segments

### Production Testing
- [ ] Feature flag toggle in production
- [ ] A/B testing: segmented vs traditional welcome
- [ ] User experience metrics (time to first audio)
- [ ] Cost analysis (parallel TTS vs single)

## 📊 Success Metrics

### User Experience
- **Time to First Audio**: Target <15 seconds (vs current 45-90s)
- **Completion Rate**: % users who complete full welcome DayStart
- **User Satisfaction**: Post-onboarding survey scores

### Technical Performance
- **Backend Processing**: Parallel generation time vs sequential
- **iOS Memory Usage**: Segmented player vs traditional player
- **Cost Impact**: TTS costs for parallel vs single generation
- **Error Rates**: Segment failures vs single-file failures

## 🚀 Deployment Plan

### Phase 1: Backend Infrastructure (Week 1)
1. Database schema updates
2. Version detection in create_job
3. Segmented script generation
4. get_audio_segment endpoint
5. Feature flag implementation

### Phase 2: iOS Implementation (Week 2)
1. SegmentedAudioPlayer class
2. HomeViewModel integration
3. Fallback mechanisms
4. Testing with backend

### Phase 3: Production Rollout (Week 3)
1. Deploy backend with feature flag OFF
2. Test in production with internal accounts
3. Gradual rollout: 10% → 50% → 100% of welcome DayStarts
4. Monitor metrics and rollback if needed

## ⚠️ Risk Assessment

### High Risk
- **Backwards Compatibility**: Breaking existing app versions
- **User Experience**: Segments not loading smoothly
- **Cost Impact**: Parallel TTS significantly more expensive

### Medium Risk  
- **iOS Memory**: Multiple audio files in memory
- **Network Usage**: Multiple API calls vs single download
- **Complexity**: More moving parts = more failure points

### Mitigation Strategies
- Comprehensive backwards compatibility testing
- Feature flag for instant rollback
- Conservative rollout with monitoring
- Cost monitoring and alerts
- Fallback to single-file for any failures

## 💰 Cost Analysis

### Current Welcome DayStart
- 1 script generation: ~$0.002
- 1 TTS request (60s): ~$0.018
- **Total per welcome: ~$0.020**

### Segmented Welcome DayStart
- 5 script generations: ~$0.010
- 5 TTS requests (12s each): ~$0.018
- 1 fallback single file: ~$0.018
- **Total per welcome: ~$0.046**

**Cost Impact**: +130% per welcome DayStart, but significantly better user experience and potentially higher conversion rates.

## 🎯 Next Steps

1. **Get approval** for cost increase and implementation approach
2. **Create feature branch** for segmented audio work
3. **Start with database migrations** (additive only)
4. **Implement backend version detection** and feature flagging
5. **Build segmented script generation** with parallel TTS
6. **Create iOS segmented player** with fallback mechanisms
7. **Test thoroughly** in development environment
8. **Deploy with feature flag OFF** for safety
9. **Gradual production rollout** with monitoring

---

*This plan prioritizes backwards compatibility and production safety while delivering a significantly improved welcome experience for new users.*