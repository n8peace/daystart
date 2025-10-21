class DayStartPlayer {
    constructor() {
        this.audio = document.getElementById('audioElement');
        this.token = this.getTokenFromUrl();
        this.isPlaying = false;
        this.init();
    }

    getTokenFromUrl() {
        const path = window.location.pathname;
        const match = path.match(/\/shared\/([^\/]+)/);
        return match ? match[1] : null;
    }

    async init() {
        if (!this.token) {
            this.showError();
            return;
        }

        try {
            await this.loadDayStart();
            this.setupControls();
            this.showPlayer();
        } catch (error) {
            console.error('Failed to load DayStart:', error);
            this.showError();
        }
    }

    async loadDayStart() {
        try {
            const response = await fetch('https://pklntrvznjhaxyxsjjgq.supabase.co/functions/v1/get_shared_daystart', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ token: this.token })
            });

            const data = await response.json();
            
            if (!response.ok) {
                // Handle specific error codes from the edge function
                switch (data.code) {
                    case 'SHARE_EXPIRED':
                        throw new Error('expired');
                    case 'AUDIO_NOT_FOUND':
                        throw new Error('audio_missing');
                    case 'INVALID_TOKEN':
                        throw new Error('invalid');
                    default:
                        throw new Error(data.error || 'Failed to load DayStart');
                }
            }
            
            // Update UI with real data
            this.updateUI(data);
            
            // Set real audio source
            if (data.audio_url) {
                this.audio.src = data.audio_url;
                // Preload metadata to get duration
                this.audio.load();
            }
            
        } catch (error) {
            console.error('Failed to load DayStart:', error);
            // Enhanced error handling
            if (error.message === 'expired') {
                this.showExpiredError();
            } else {
                throw error; // Let the init() method handle other errors
            }
        }
    }

    updateUI(data) {
        // Format date nicely
        const dateObj = new Date(data.date);
        const dateElement = document.getElementById('daystartDate');
        if (dateElement) {
            dateElement.textContent = dateObj.toLocaleDateString('en-US', { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric' 
            });
        }
        
        // Duration with personalized touch
        const userName = data.user_name ? `${data.user_name}'s ` : '';
        const durationElement = document.getElementById('durationInfo');
        if (durationElement) {
            durationElement.textContent = `${userName}${data.length_minutes} minute intelligence brief`;
        }
        
        // Update page title and social meta tags dynamically
        const shareTitle = `Listen to ${userName}Morning Intelligence Brief`;
        const shareDescription = `${data.length_minutes} minutes of curated insights delivered like a Chief of Staff prepared it. Stop reacting. Start leading.`;
        
        // Update page title
        document.title = shareTitle;
        
        // Update Open Graph tags for better social sharing
        this.updateMetaTag('property', 'og:title', shareTitle);
        this.updateMetaTag('property', 'og:description', shareDescription);
        this.updateMetaTag('property', 'og:url', window.location.href);
        
        // Update Twitter Card
        this.updateMetaTag('name', 'twitter:title', shareTitle);
        this.updateMetaTag('name', 'twitter:description', shareDescription);

        // Audio source is now set in loadDayStart()
    }
    
    updateMetaTag(attribute, attributeValue, content) {
        const selector = `meta[${attribute}="${attributeValue}"]`;
        const tag = document.querySelector(selector);
        if (tag) {
            tag.content = content;
        }
    }

    setupControls() {
        const playPause = document.getElementById('playPause');
        const skipBack = document.getElementById('skipBack');
        const skipForward = document.getElementById('skipForward');
        const progressBar = document.getElementById('progressBar');

        if (playPause) {
            playPause.addEventListener('click', () => this.togglePlayPause());
        }
        
        if (skipBack) {
            skipBack.addEventListener('click', () => this.skip(-10));
        }
        
        if (skipForward) {
            skipForward.addEventListener('click', () => this.skip(10));
        }
        
        if (progressBar) {
            progressBar.addEventListener('click', (e) => this.seek(e));
        }

        // Audio event listeners
        this.audio.addEventListener('timeupdate', () => this.updateProgress());
        this.audio.addEventListener('loadedmetadata', () => this.updateDuration());
        this.audio.addEventListener('play', () => this.onPlay());
        this.audio.addEventListener('pause', () => this.onPause());
        this.audio.addEventListener('ended', () => this.onEnded());
    }

    togglePlayPause() {
        if (this.audio.paused) {
            this.audio.play().catch(error => {
                console.error('Playback failed:', error);
                // Show user-friendly error if playback fails
                const errorElement = document.getElementById('error');
                if (errorElement) {
                    errorElement.querySelector('p').textContent = 'Unable to play audio';
                    errorElement.style.display = 'block';
                    document.getElementById('playerControls').style.display = 'none';
                }
            });
        } else {
            this.audio.pause();
        }
    }


    skip(seconds) {
        if (this.audio.duration) {
            this.audio.currentTime = Math.max(0, Math.min(this.audio.duration, this.audio.currentTime + seconds));
        }
    }

    seek(e) {
        const progressBar = e.currentTarget;
        const rect = progressBar.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        
        if (this.audio.duration) {
            this.audio.currentTime = percent * this.audio.duration;
        }
    }

    updateProgress() {
        if (!this.audio.duration) return;
        
        const percent = (this.audio.currentTime / this.audio.duration) * 100;
        const progressFill = document.getElementById('progressFill');
        const currentTimeElement = document.getElementById('currentTime');
        
        if (progressFill) {
            progressFill.style.width = percent + '%';
        }
        
        if (currentTimeElement) {
            currentTimeElement.textContent = this.formatTime(this.audio.currentTime);
        }
    }

    updateDuration() {
        const durationElement = document.getElementById('duration');
        if (durationElement && this.audio.duration) {
            durationElement.textContent = this.formatTime(this.audio.duration);
        }
    }

    onPlay() {
        const button = document.getElementById('playPause');
        if (button) {
            button.textContent = '⏸️';
        }
    }

    onPause() {
        const button = document.getElementById('playPause');
        if (button) {
            button.textContent = '▶️';
        }
    }

    onEnded() {
        const button = document.getElementById('playPause');
        if (button) {
            button.textContent = '▶️';
        }
        
        // Reset progress
        const progressFill = document.getElementById('progressFill');
        if (progressFill) {
            progressFill.style.width = '0%';
        }
        
        const currentTimeElement = document.getElementById('currentTime');
        if (currentTimeElement) {
            currentTimeElement.textContent = this.formatTime(0);
        }
    }

    formatTime(seconds) {
        if (isNaN(seconds)) return '0:00';
        
        const mins = Math.floor(seconds / 60);
        const secs = Math.floor(seconds % 60);
        return `${mins}:${secs.toString().padStart(2, '0')}`;
    }

    showPlayer() {
        const loading = document.getElementById('loading');
        const playerControls = document.getElementById('playerControls');
        
        if (loading) {
            loading.style.display = 'none';
        }
        
        if (playerControls) {
            playerControls.style.display = 'block';
        }
    }

    showError() {
        const loading = document.getElementById('loading');
        const error = document.getElementById('error');
        
        if (loading) {
            loading.style.display = 'none';
        }
        
        if (error) {
            error.style.display = 'block';
        }
    }
    
    showExpiredError() {
        const loading = document.getElementById('loading');
        const error = document.getElementById('error');
        
        if (loading) {
            loading.style.display = 'none';
        }
        
        if (error) {
            const errorText = error.querySelector('p');
            if (errorText) {
                errorText.textContent = 'This briefing has expired';
            }
            const errorSubtext = error.querySelector('.error-subtext');
            if (errorSubtext) {
                errorSubtext.textContent = 'Share links expire after 48 hours for security.';
            }
            error.style.display = 'block';
        }
    }
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    new DayStartPlayer();
});