import Foundation

class MockDataService {
    static let shared = MockDataService()
    
    private init() {}
    
    func generateMockDayStart(for settings: UserSettings) async -> DayStartData {
        // Simulate API delay
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
        
        let weather = generateMockWeather()
        let news = generateMockNews()
        let sports = generateMockSports()
        let stocks = generateMockStocks(symbols: settings.stockSymbols)
        let quote = generateMockQuote(preference: settings.quotePreference)
        let transcript = generateMockTranscript(
            name: settings.preferredName,
            weather: weather,
            news: news,
            sports: sports,
            stocks: stocks,
            quote: quote,
            customPrompt: "",
            settings: settings
        )
        
        return DayStartData(
            date: Date(),
            weather: weather,
            news: news,
            sports: sports,
            stocks: stocks,
            quote: quote,
            customPrompt: "",
            transcript: transcript,
            duration: Double(settings.dayStartLength * 60),
            audioFilePath: nil
        )
    }
    
    // Earlier simple fetch used by HomeViewModel legacy
    func fetchDayStart(for settings: UserSettings) -> DayStartData {
        let weather = generateMockWeather()
        let news = generateMockNews()
        let sports = generateMockSports()
        let stocks = generateMockStocks(symbols: settings.stockSymbols)
        let quote = generateMockQuote(preference: settings.quotePreference)
        let transcript = generateMockTranscript(
            name: settings.preferredName,
            weather: weather,
            news: news,
            sports: sports,
            stocks: stocks,
            quote: quote,
            customPrompt: "",
            settings: settings
        )
        return DayStartData(
            date: Date(),
            weather: weather,
            news: news,
            sports: sports,
            stocks: stocks,
            quote: quote,
            customPrompt: "",
            transcript: transcript,
            duration: Double(settings.dayStartLength * 60),
            audioFilePath: nil
        )
    }
    
    private func generateMockWeather() -> String {
        let conditions = ["sunny", "partly cloudy", "overcast", "light rain", "clear skies"]
        let temperatures = Array(65...85)
        
        let condition = conditions.randomElement() ?? "sunny"
        let temp = temperatures.randomElement() ?? 72
        
        return "Currently \(condition) with a temperature of \(temp)°F"
    }
    
    private func generateMockNews() -> [String] {
        return [
            "Tech stocks rally as AI adoption accelerates across industries",
            "Scientists discover breakthrough in renewable energy storage",
            "Global climate summit reaches historic agreement on emissions",
            "New medical research shows promise for treating chronic diseases",
            "Space exploration mission successfully lands on distant planet"
        ].shuffled().prefix(3).map { $0 }
    }
    
    private func generateMockSports() -> [String] {
        let teams = ["Lakers", "Warriors", "Celtics", "Heat", "Knicks", "Bulls"]
        let results = teams.shuffled().prefix(2)
        
        return [
            "\(results[0]) defeated \(results[1]) 108-95 in last night's game",
            "Baseball season continues with exciting playoff races",
            "Tennis championship finals set for this weekend"
        ].shuffled().prefix(2).map { $0 }
    }
    
    private func generateMockStocks(symbols: [String]) -> [String] {
        return symbols.map { symbol in
            let change = Double.random(in: -5.0...5.0)
            let price = Double.random(in: 50...200)
            let changeString = change >= 0 ? "+\(String(format: "%.2f", change))" : String(format: "%.2f", change)
            return "\(symbol): $\(String(format: "%.2f", price)) (\(changeString)%)"
        }
    }
    
    private func generateMockQuote(preference: QuotePreference) -> String {
        let quotes: [QuotePreference: [String]] = [
            .inspirational: [
                "The only way to do great work is to love what you do. - Steve Jobs",
                "Innovation distinguishes between a leader and a follower. - Steve Jobs",
                "Your limitation—it's only your imagination.",
                "Don't wait for opportunity. Create it."
            ],
            .stoic: [
                "You have power over your mind - not outside events. Realize this, and you will find strength. - Marcus Aurelius",
                "The happiness of your life depends upon the quality of your thoughts. - Marcus Aurelius",
                "It never ceases to amaze me: we all love ourselves more than other people, but care more about their opinion than our own. - Marcus Aurelius"
            ],
            .mindfulness: [
                "The present moment is the only time over which we have dominion. - Thích Nhất Hạnh",
                "Mindfulness is about being fully awake in our lives. - Jon Kabat-Zinn",
                "Peace comes from within. Do not seek it without. - Buddha"
            ],
            .success: [
                "Success is not final, failure is not fatal: it is the courage to continue that counts. - Winston Churchill",
                "Don't be afraid to give up the good to go for the great. - John D. Rockefeller",
                "The way to get started is to quit talking and begin doing. - Walt Disney"
            ],
            .philosophical: [
                "The unexamined life is not worth living. - Socrates",
                "We are what we repeatedly do. Excellence, then, is not an act, but a habit. - Aristotle",
                "The only true wisdom is in knowing you know nothing. - Socrates"
            ],
            .zen: [
                "Let go or be dragged. - Zen Proverb",
                "You are perfect as you are, and you could use a little improvement. - Shunryu Suzuki",
                "The pine teaches silence, the rock teaches stillness. - Buddhist Proverb"
            ],
            .goodFeelings: [
                "Choose to be optimistic, it feels better. - Dalai Lama",
                "Happiness is not something ready made. It comes from your own actions. - Dalai Lama",
                "A grateful heart is a magnet for miracles."
            ],
            .buddhist: [
                "Peace comes from within. Do not seek it without. - Buddha",
                "The mind is everything. What you think you become. - Buddha",
                "Three things cannot be long hidden: the sun, the moon, and the truth. - Buddha"
            ],
            .christian: [
                "I can do all things through Christ who strengthens me. - Philippians 4:13",
                "Trust in the Lord with all your heart. - Proverbs 3:5",
                "Be strong and courageous. Do not be afraid. - Joshua 1:9"
            ],
            .hindu: [
                "You are what your deep, driving desire is. - Brihadaranyaka Upanishad",
                "The mind acts like an enemy for those who do not control it. - Bhagavad Gita",
                "Change is the law of the universe. - Bhagavad Gita"
            ],
            .jewish: [
                "If I am not for myself, who will be for me? - Hillel the Elder",
                "Who is rich? One who is happy with their lot. - Pirkei Avot",
                "In a place where there are no human beings, strive to be human. - Pirkei Avot"
            ],
            .muslim: [
                "And whoever relies upon Allah - then He is sufficient for him. - Quran 65:3",
                "And Allah is the best of planners. - Quran 8:30",
                "Indeed, with hardship comes ease. - Quran 94:6"
            ]
        ]
        
        let categoryQuotes = quotes[preference] ?? quotes[.inspirational]!
        return categoryQuotes.randomElement() ?? "Today is a new day full of possibilities."
    }
    
    private func generateMockTranscript(
        name: String,
        weather: String,
        news: [String],
        sports: [String],
        stocks: [String],
        quote: String,
        customPrompt: String,
        settings: UserSettings
    ) -> String {
        var transcript = ""
        
        // Greeting
        let greeting = name.isEmpty ? "Good morning!" : "Good morning, \(name)!"
        transcript += "\(greeting) Welcome to your DayStart briefing for \(formatDate(Date())). "
        
        // Weather
        if settings.includeWeather {
            transcript += "Let's start with the weather. \(weather). "
        }
        
        // News
        if settings.includeNews && !news.isEmpty {
            transcript += "In today's news: "
            transcript += news.joined(separator: ". ")
            transcript += ". "
        }
        
        // Sports
        if settings.includeSports && !sports.isEmpty {
            transcript += "Sports update: "
            transcript += sports.joined(separator: ". ")
            transcript += ". "
        }
        
        // Stocks
        if settings.includeStocks && !stocks.isEmpty {
            transcript += "Market update: "
            transcript += stocks.joined(separator: ", ")
            transcript += ". "
        }
        
        // Quote
        if settings.includeQuotes {
            transcript += "Here's your daily inspiration: \(quote) "
        }
        
        // Custom prompt
        if !customPrompt.isEmpty {
            transcript += customPrompt + " "
        }
        
        // Closing
        transcript += "That's your DayStart briefing. Have a wonderful day!"
        
        return transcript
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
    
    // Generate mock historical data
    func generateMockHistory(count: Int = 10) -> [DayStartData] {
        let calendar = Calendar.current
        let now = Date()
        
        var items: [DayStartData] = (0..<count).compactMap { dayOffset -> DayStartData? in
            guard let date = calendar.date(byAdding: .day, value: -dayOffset, to: now) else { return nil }
            
            let mockSettings = UserSettings.default
            let weather = generateMockWeather()
            let news = generateMockNews()
            let sports = generateMockSports()
            let stocks = generateMockStocks(symbols: ["AAPL", "TSLA", "SPY"])
            let quote = generateMockQuote(preference: .inspirational)
            
            // Determine audio availability:
            // - Most recent item (dayOffset == 0): attach bundled voice1 audio
            // - Items older than 7 days: mark as deleted
            // - Others: no audio
            let bundledPath: String? = {
                if dayOffset == 0 {
                    return Bundle.main.path(forResource: "ai_wakeup_generic_voice1", ofType: "mp3")
                }
                return nil
            }()
            let isDeleted = dayOffset > 7

            return DayStartData(
                date: date,
                weather: weather,
                news: news,
                sports: sports,
                stocks: stocks,
                quote: quote,
                customPrompt: "",
                transcript: generateMockTranscript(
                    name: "User",
                    weather: weather,
                    news: news,
                    sports: sports,
                    stocks: stocks,
                    quote: quote,
                    customPrompt: "",
                    settings: mockSettings
                ),
                duration: Double.random(in: 180...420), // 3-7 minutes
                audioFilePath: bundledPath,
                isDeleted: isDeleted
            )
        }

        // Add a specific sample entry dated Aug 8, 2025 with bundled audio for testing
        if let targetDate = Calendar.current.date(from: DateComponents(year: 2025, month: 8, day: 8)) {
            let sample = DayStartData(
                date: targetDate,
                weather: generateMockWeather(),
                news: generateMockNews(),
                sports: generateMockSports(),
                stocks: generateMockStocks(symbols: ["AAPL", "TSLA", "SPY"]),
                quote: generateMockQuote(preference: .inspirational),
                customPrompt: "",
                transcript: "Sample DayStart audio for Aug 8, 2025.",
                duration: 240,
                audioFilePath: Bundle.main.path(forResource: "ai_wakeup_generic_voice1", ofType: "mp3"),
                isDeleted: false
            )
            items.insert(sample, at: 0)
        }

        return items
    }
}