### ElevenLabs TTS – DayStart

This document captures voice choices, prompt recipes, and API usage for ElevenLabs Text-to-Speech in DayStart.

### Goals
- Produce consistent, fast, natural audio for wake-ups and short narratives.
- Keep voices opinionated and limited to a small curated set.
- Make prompting repeatable and easy to tweak without code changes.

### Current Voices (inventory)
- Default voice: `voice_1` – Grace — warm, smooth, versatile.
- Additional voices:
  - `voice_2` – Rachel — clear, authoritative, well-paced (headline delivery).
  - `voice_3` – Matthew — calm, composed, narrative-ready.

Fill in final selections below once chosen:

| Internal ID | Display Name | elevenlabs voice_id | Style Tags | Primary Use | Sample Asset | Status |
|---|---|---|---|---|---|---|
| voice_1 | Grace | wdRkW5c5eYi8vKR8E4V9 | warm, smooth, versatile | feature-style headlines, human-interest intros; gentle wake | DayStart/Resources/Sounds/ai_wakeup_generic_voice1.mp3 | selected |
| voice_2 | Rachel | 21m00Tcm4TlvDq8ikWAM | clear, authoritative, well-paced | headline delivery | DayStart/Resources/Sounds/ai_wakeup_generic_voice2.mp3 | selected |
| voice_3 | Matthew | QczW7rKFMVYyubTC1QDk | calm, composed, narrative-ready | steady, thoughtful delivery (public-radio style) | DayStart/Resources/Sounds/ai_wakeup_generic_voice3.mp3 | selected |

Guidelines:
- Keep 3–4 voices max to avoid choice overload.
- Each voice should own distinct use-cases to reduce subjective swaps.

### Prompt Recipes (text generation before TTS)
General rules:
- Keep scripts concise; aim 10–35 seconds of speech (≈ 25–90 words).
- Avoid the year in any date references.
- Prefer declarative present-tense phrasing.

Recipe: gentle_morning (pairs with `voice_1`)
- Tone: warm, encouraging, unhurried.
- Structure:
  1) Soft greeting with name (if available)
  2) One short focus for today
  3) One positive nudge, one breath cue
  4) Close with a calm call-to-action

Template:
"Good morning{, {name}}. Today’s focus is {focus}. Take a slow breath in. And out. You’re on track. When you’re ready, {first_action}."

Recipe: drill_sergeant (pairs with `voice_2`)
- Tone: brisk, motivational, short sentences.
- Template:
"Up and at it{, {name}}. Today: {focus}. Hydrate. Move. Execute {first_action} now. You’ve got this."

Recipe: narrative_news (pairs with `voice_3`)
- Tone: neutral, informative, brief.
- Template:
"Here’s your quick brief. {headline_1}. {headline_2}. {headline_3}. Action for today: {first_action}."

### ElevenLabs API – Request Template
Endpoint (text-to-speech streaming or non-streaming may be used; choose per scenario):
- POST `https://api.elevenlabs.io/v1/text-to-speech/{voice_id}`

Headers:
- `xi-api-key: <secret>`
- `accept: audio/mpeg`
- `content-type: application/json`

Body (baseline settings):
```json
{
  "text": "Good morning. Today’s focus is momentum. Take a slow breath in. And out.",
  "model_id": "eleven_multilingual_v2",
  "voice_settings": {
    "stability": 0.45,
    "similarity_boost": 0.85,
    "style": 0.0,
    "use_speaker_boost": true
  },
  "optimize_streaming_latency": 2,
  "output_format": "mp3_44100_128"
}
```

Notes:
- `optimize_streaming_latency`: 0–4 (higher trades quality for latency). Use 2–3 for wake-up snappiness, 0–1 for maximum quality in background jobs.
- `output_format`: mp3 at 44.1kHz/128kbps balances speed and quality for iOS.

### Audio Handling & File Conventions
- File type: mp3, mono, 44.1kHz recommended.
- Naming: `ai_wakeup_<scenario>_voice<idx>.mp3`.
- Store generated canonical samples in `DayStart/Resources/Sounds/` when applicable.
- Keep previews ≤ 500KB where possible for quick iteration.

### Quality Tuning
- If audio sounds flat: raise `stability` slightly; if too variable, lower it.
- If voice deviates from intended timbre: raise `similarity_boost`.
- For more expressive reads: increase `style` incrementally (0.2–0.5).

### Operational Notes
- Keep API keys in secure envs; never in the iOS client.
- For background generation, non-streaming requests are acceptable; save to storage then fetch.
- For immediate wake flow, use streaming with small `optimize_streaming_latency` when needed.

### Voice Selection Checklist (to complete)
- [ ] Finalize `display name` and `voice_id` for each voice.
- [ ] Save 10–20s canonical sample per voice.
- [ ] Confirm baseline `voice_settings` per voice.
- [ ] Verify volume normalization is consistent across voices.

### Open Questions
- Do we want a fourth voice for fun/seasonal events?
- Should narrative voice use higher quality settings and non-streamed path exclusively?


