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
        // For now, we'll create a mock response until the backend is set up
        // This will be replaced with the actual Supabase function call
        
        // Mock data for testing
        const mockData = {
            audio_url: 'https://www.soundjay.com/misc/sounds/bell-ringing-05.wav', // Placeholder
            duration: 180, // 3 minutes
            date: new Date().toISOString(),
            length_minutes: 3
        };

        // Uncomment this when backend is ready:
        /*
        const response = await fetch('https://your-supabase-project.supabase.co/functions/v1/get_shared_daystart', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ token: this.token })
        });

        if (!response.ok) throw new Error('Failed to load DayStart');
        const data = await response.json();
        */

        const data = mockData;
        
        // For testing, we'll simulate loading without actual audio
        // Remove this setTimeout when using real audio
        setTimeout(() => {
            this.updateUI(data);
        }, 1000);
    }

    updateUI(data) {
        // Update date display
        const dateElement = document.getElementById('daystartDate');
        if (dateElement) {
            dateElement.textContent = new Date(data.date).toLocaleDateString('en-US', { 
                weekday: 'long', 
                year: 'numeric', 
                month: 'long', 
                day: 'numeric' 
            });
        }
        
        // Update duration info
        const durationElement = document.getElementById('durationInfo');
        if (durationElement) {
            durationElement.textContent = `${data.length_minutes} minute briefing`;
        }

        // Set audio source (commented out for testing)
        // this.audio.src = data.audio_url;
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
        const button = document.getElementById('playPause');
        
        if (this.audio.src && this.audio.src !== window.location.href) {
            // Real audio
            if (this.audio.paused) {
                this.audio.play();
            } else {
                this.audio.pause();
            }
        } else {
            // Mock playback for testing
            this.isPlaying = !this.isPlaying;
            if (button) {
                button.textContent = this.isPlaying ? '⏸️' : '▶️';
            }
            
            if (this.isPlaying) {
                this.startMockProgress();
            } else {
                this.stopMockProgress();
            }
        }
    }

    startMockProgress() {
        this.mockCurrentTime = this.mockCurrentTime || 0;
        this.mockDuration = 180; // 3 minutes
        
        this.mockInterval = setInterval(() => {
            if (this.isPlaying && this.mockCurrentTime < this.mockDuration) {
                this.mockCurrentTime += 1;
                this.updateMockProgress();
            } else if (this.mockCurrentTime >= this.mockDuration) {
                this.onEnded();
            }
        }, 1000);
    }

    stopMockProgress() {
        if (this.mockInterval) {
            clearInterval(this.mockInterval);
        }
    }

    updateMockProgress() {
        const percent = (this.mockCurrentTime / this.mockDuration) * 100;
        const progressFill = document.getElementById('progressFill');
        const currentTimeElement = document.getElementById('currentTime');
        const durationElement = document.getElementById('duration');
        
        if (progressFill) {
            progressFill.style.width = percent + '%';
        }
        
        if (currentTimeElement) {
            currentTimeElement.textContent = this.formatTime(this.mockCurrentTime);
        }
        
        if (durationElement) {
            durationElement.textContent = this.formatTime(this.mockDuration);
        }
    }

    skip(seconds) {
        if (this.audio.src && this.audio.src !== window.location.href) {
            this.audio.currentTime = Math.max(0, Math.min(this.audio.duration, this.audio.currentTime + seconds));
        } else {
            // Mock skip
            this.mockCurrentTime = Math.max(0, Math.min(this.mockDuration || 180, (this.mockCurrentTime || 0) + seconds));
            this.updateMockProgress();
        }
    }

    seek(e) {
        const progressBar = e.currentTarget;
        const rect = progressBar.getBoundingClientRect();
        const percent = (e.clientX - rect.left) / rect.width;
        
        if (this.audio.src && this.audio.src !== window.location.href) {
            this.audio.currentTime = percent * this.audio.duration;
        } else {
            // Mock seek
            this.mockCurrentTime = percent * (this.mockDuration || 180);
            this.updateMockProgress();
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
        
        this.isPlaying = false;
        this.stopMockProgress();
        
        // Reset progress
        const progressFill = document.getElementById('progressFill');
        if (progressFill) {
            progressFill.style.width = '0%';
        }
        
        this.mockCurrentTime = 0;
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
}

// Initialize when page loads
document.addEventListener('DOMContentLoaded', () => {
    new DayStartPlayer();
});