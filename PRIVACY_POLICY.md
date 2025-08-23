## Privacy Policy

Effective Date: [Month Day, Year]

Banana Intelligence LLC ("Banana Intelligence", "we", "us", or "our") operates the DayStart AI mobile application (the "App"). This Privacy Policy describes how we collect, use, disclose, and protect information when you use the App. By using the App, you agree to this Policy.

### 1. Who we are and how to contact us
- Legal entity: [Banana Intelligence LLC full legal name]
- Registered address: [Address]
- Contact: [Privacy contact email]
- Data Protection Officer (if applicable): [Name/Contact]

### 2. What we collect
We designed DayStart AI to minimize personal data. The App does not create a traditional account. Instead, it uses your Apple purchase receipt identifier as a pseudonymous user ID. Depending on how you use the App and which features you enable, we may process:

- **Purchase identifier**: Original StoreKit transaction/receipt ID stored locally in the device Keychain and sent as a header to our backend to authenticate access. We do not receive your payment card details (handled by Apple).
- **App settings and schedule**: Your preferences (e.g., voice selection, included content types, schedule time, repeat days) stored on‑device and sent to our backend when needed to generate your briefing.
- **Location data (optional)**: If enabled, we request "When In Use" location permission to obtain your approximate location for local weather. We may derive city, state, country, neighborhood and include approximate coordinates for weather retrieval. Derived location details can be sent to our backend solely to generate your briefing.
- **Calendar data (optional)**: If enabled, we request Calendar access to read event titles and times for your upcoming events. We format this locally into short text lines (e.g., "Meeting at 9:00 AM") and may include those lines in the context we send to our backend to personalize your briefing. We do not access attendees, notes, attachments, or invitee lists.
- **Notifications**: The App uses local notifications to remind you about upcoming briefings. We do not collect Apple Push Notification tokens.
- **Device and usage diagnostics**: In‑app diagnostic logging (via Apple OSLog) is used for debugging and performance. We do not collect a device advertising identifier. Server‑side request logs may record timestamps, request IDs, IP addresses (by our hosting provider), headers necessary for authentication, and error codes.
- **Generated audio and job metadata**: The generated audio file for your briefing and related job metadata (e.g., job ID, selected content flags, timestamps) are stored on our backend for delivery and troubleshooting.

### 3. How we use information
We use the information described above to:
- generate your DayStart briefing (script and audio);
- provide features you request (weather, stocks, sports, calendar);
- operate, secure, and improve the App and backend;
- comply with legal obligations and enforce terms.

### 4. Data sharing and third parties
We share data only as needed to operate the App:
- **Backend hosting and storage (Supabase)**: We host APIs, databases, and storage with Supabase. Generated audio files are stored in Supabase Storage; job records and request logs are stored in Supabase Postgres.
- **AI and text‑to‑speech providers**: We use third‑party models and TTS providers to generate and render briefings (e.g., OpenAI for script generation; ElevenLabs or similar for TTS). We send only the minimal context needed (e.g., preferences, compact news/sports/stocks summaries, optional location city/state and calendar lines if you enable those features).
- **Content/data sources**: We retrieve content from public/partner sources (e.g., news via NewsAPI/GNews, sports via ESPN/TheSportDB, market data via Yahoo Finance on RapidAPI [[memory:3578210]], Apple WeatherKit for weather). We generally do not send your personal data to these sources; we fetch public data and then process it for your briefing.
- **Apple services**: StoreKit (purchases), WeatherKit (weather), and EventKit (calendar) operate subject to Apple’s terms and your permissions.
- **Service providers and legal**: We may disclose information to service providers under contract who process data on our behalf, and as required by law or to protect rights and safety.

We do not sell your personal information.

### 5. Retention
- **Audio files**: Automatically cleaned from storage after approximately 10 days.
- **Job and request records**: Operational job records and related metadata are typically removed or compacted after approximately 30 days.
- **Device‑local data**: Preferences and the purchase receipt ID are stored on your device (Keychain/UserDefaults) until you change them or uninstall the App.
Actual retention periods may vary due to operational needs, legal requirements, or system constraints.

### 6. Your choices
- **Location and Calendar**: These are optional. You can disable them at any time in iOS Settings > Privacy or inside the App settings screens; the App will function with reduced personalization.
- **Notifications**: You can manage local notification permissions in iOS Settings.
- **Access, correction, deletion**: Because we do not maintain traditional user accounts, requests may require device verification. You may request deletion of backend job/audio data associated with your pseudonymous receipt ID by contacting us at [Privacy contact email]. Uninstalling the App removes device‑local data under our control (excluding Apple/OS logs and standard platform backups outside our control).

### 7. Legal bases (EEA/UK)
Where GDPR/UK GDPR applies, we process:
- to perform the contract (provide the Service) when generating your briefing and delivering content;
- based on your consent for optional Location and Calendar access;
- for our legitimate interests in operating, securing, and improving the Service (balanced against your rights).

### 8. International data transfers
We may process data in the United States and other countries where our providers operate. Where required, we use appropriate safeguards (e.g., standard contractual clauses) for international transfers.

### 9. Security
We use reasonable administrative, technical, and physical safeguards to protect data, including TLS in transit and device Keychain storage for the receipt identifier. No system is 100% secure.

### 10. Children’s privacy
The App is not directed to children under 13, and we do not knowingly collect personal information from children under 13. If you believe a child provided personal information, contact us to request deletion.

### 11. Changes to this Policy
We may update this Policy from time to time. Material changes will be communicated in‑app or via update notes. The Effective Date will be updated, and continued use constitutes acceptance.

### 12. Contact
If you have questions or requests regarding privacy, contact us at: [Privacy contact email] or mail: [Address].

### 13. Additional information
- Account model: The App identifies users using a pseudonymous Apple purchase receipt ID and does not require creating a username/password.
- Permissions summary: Location (When In Use) for weather, Calendar for event summaries, Local notifications for reminders.
- Data minimization: Calendar lines are summarized locally (title/time only) before optional inclusion in backend requests; we avoid sending full event details.


