import SwiftUI
import StoreKit

struct PaywallView: View {
    @Environment(\.dismiss) private var dismiss
    
    // StoreKit integration
    @StateObject private var purchaseManager = PurchaseManager.shared
    
    // UI state
    @State private var selectedProductID: String = "daystart_monthly_subscription"
    @State private var isLoading = false
    @State private var showingError = false
    @State private var errorMessage = ""
    @State private var animationTrigger = false
    
    // Animation properties
    @State private var heroScale: CGFloat = 1.0
    @State private var starRotation: Double = 0
    
    private let logger = DebugLogger.shared
    
    // Completion handlers
    let onPurchaseComplete: (() -> Void)?
    let onDismiss: (() -> Void)?
    
    init(
        onPurchaseComplete: (() -> Void)? = nil,
        onDismiss: (() -> Void)? = nil
    ) {
        self.onPurchaseComplete = onPurchaseComplete
        self.onDismiss = onDismiss
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Main scrollable content
                ScrollView {
                    LazyVStack(spacing: 0) {
                        // Header section
                        headerSection(geometry: geometry)
                        
                        Spacer(minLength: max(20, geometry.size.height * 0.02))
                        
                        // Pricing and purchase section content (without buttons)
                        VStack(spacing: 12) {
                            subscriptionPlansSection(geometry: geometry)
                        }
                        .padding(.horizontal, geometry.size.width * 0.10)
                        
                        Spacer(minLength: max(180, geometry.size.height * 0.30))
                    }
                }
                .scrollIndicators(.hidden)
                
                // Fixed bottom purchase button and footer
                VStack(spacing: 16) {
                    OnboardingBottomButton(
                        buttonText: isLoading ? "Processing..." : getPurchaseButtonText(),
                        action: {
                            startPurchaseFlow()
                        },
                        geometry: geometry,
                        animationTrigger: animationTrigger,
                        textOpacity: 1.0,
                        poweredByText: getSelectedProduct().flatMap { getPurchaseButtonSubtext(for: $0) },
                        poweredByURL: nil
                    )
                    .disabled(isLoading || purchaseManager.isLoadingProducts)
                    
                    // Footer section
                    footerSection(geometry: geometry)
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 10)
                        .background(BananaTheme.ColorToken.background)
                }
            }
            .background(
                ZStack {
                    // Standard background pattern (matches onboarding and rest of app)
                    BananaTheme.ColorToken.background
                        .ignoresSafeArea()
                    
                    // Subtle gradient overlay (15% opacity like onboarding)
                    DayStartGradientBackground()
                        .opacity(0.15)
                }
            )
        }
        .onAppear {
            logger.log("💳 PaywallView appeared", level: .info)
            startAnimations()
            fetchProductsIfNeeded()
        }
        .alert("Purchase Error", isPresented: $showingError) {
            Button("OK") { }
        } message: {
            Text(errorMessage)
        }
        .navigationBarHidden(true)
    }
    
    
    // MARK: - Sections
    
    private func headerSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 16) {
            heroSection
        }
        .padding(.horizontal, max(20, geometry.size.width * 0.05))
        .padding(.top, max(40, geometry.safeAreaInsets.top + 40))
    }
    
    
    private var heroSection: some View {
        VStack(spacing: 16) {
            heroIcon
            heroText
        }
    }
    
    private var heroIcon: some View {
        ZStack {
            // Animated background circle
            Circle()
                .fill(BananaTheme.ColorToken.primary.opacity(0.2))
                .frame(width: 120, height: 120)
                .scaleEffect(heroScale)
            
            // Main sun icon
            Text("☀️")
                .font(.system(size: 64))
                .scaleEffect(heroScale)
            
            // Animated stars
            animatedStars
        }
    }
    
    private var animatedStars: some View {
        ForEach(0..<3) { index in
            starView(for: index)
        }
    }
    
    private func starView(for index: Int) -> some View {
        let angle = Double(index) * 2 * .pi / 3 + starRotation * .pi / 180
        let xOffset = cos(angle) * 60
        let yOffset = sin(angle) * 60
        
        return Image(systemName: "star.fill")
            .font(.system(size: 12))
            .foregroundColor(BananaTheme.ColorToken.primary)
            .offset(x: xOffset, y: yOffset)
            .opacity(animationTrigger ? 1.0 : 0.3)
    }
    
    private var heroText: some View {
        VStack(spacing: 8) {
            Text("Unlock Better Days")
                .font(.system(size: 28, weight: .bold))
                .foregroundColor(BananaTheme.ColorToken.text)
                .multilineTextAlignment(.center)
            
            Text("Start every day perfectly informed")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                .multilineTextAlignment(.center)
        }
    }
    
    
    private func subscriptionPlansSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            if purchaseManager.isLoadingProducts {
                ProgressView()
                    .scaleEffect(1.2)
                    .frame(height: 100)
            } else if purchaseManager.availableProducts.isEmpty {
                VStack(spacing: 12) {
                    Text("Unable to load subscription options")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText)
                    
                    Button("Retry") {
                        fetchProductsIfNeeded()
                    }
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(BananaTheme.ColorToken.primary)
                }
                .frame(height: 100)
            } else {
                subscriptionCards(geometry: geometry)
            }
        }
    }
    
    private func subscriptionCards(geometry: GeometryProxy) -> some View {
        let weeklyProduct = getProduct(for: "daystart_weekly_subscription")
        let monthlyProduct = getProduct(for: "daystart_monthly_subscription")
        let annualProduct = getProduct(for: "daystart_annual_subscription")
        
        return VStack(spacing: 16) {
            // Weekly Plan
            if let product = weeklyProduct {
                SubscriptionPlanCard(
                    product: product,
                    title: "Weekly",
                    badge: nil, // "Try It Out",
                    badgeColor: .blue,
                    isSelected: selectedProductID == product.id,
                    geometry: geometry,
                    purchaseManager: purchaseManager,
                    animationTrigger: animationTrigger
                ) {
                    selectedProductID = product.id
                    impactFeedback()
                }
            }
            
            // Monthly Plan
            if let product = monthlyProduct {
                SubscriptionPlanCard(
                    product: product,
                    title: "Monthly",
                    badge: nil,
                    badgeColor: BananaTheme.ColorToken.primary,
                    isSelected: selectedProductID == product.id,
                    geometry: geometry,
                    purchaseManager: purchaseManager,
                    animationTrigger: animationTrigger,
                    weeklyProduct: weeklyProduct,
                    trialText: "Includes 3-day free trial"
                ) {
                    selectedProductID = product.id
                    impactFeedback()
                }
            }
            
            // Annual Plan  
            if let product = annualProduct {
                SubscriptionPlanCard(
                    product: product,
                    title: "Annual",
                    badge: nil,
                    badgeColor: BananaTheme.ColorToken.primary,
                    isSelected: selectedProductID == product.id,
                    geometry: geometry,
                    purchaseManager: purchaseManager,
                    animationTrigger: animationTrigger,
                    savings: getSavingsText(annual: product, monthly: monthlyProduct),
                    weeklyProduct: weeklyProduct,
                    trialText: "Includes 7-day free trial"
                ) {
                    selectedProductID = product.id
                    impactFeedback()
                }
            }
        }
    }
    
    
    private func footerSection(geometry: GeometryProxy) -> some View {
        VStack(spacing: 8) {
            // Footer links
            HStack(spacing: 8) {
                Button(action: {
                    Task {
                        await restorePurchases()
                    }
                }) {
                    Text("Restore Purchases")
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                }
                
                Text("•")
                    .font(.system(size: min(12, geometry.size.width * 0.03)))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                
                Button(action: {
                    if let url = URL(string: "https://daystart.bananaintelligence.ai/terms") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Terms")
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                }
                
                Text("•")
                    .font(.system(size: min(12, geometry.size.width * 0.03)))
                    .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                
                Button(action: {
                    if let url = URL(string: "https://daystart.bananaintelligence.ai/privacy") {
                        UIApplication.shared.open(url)
                    }
                }) {
                    Text("Privacy")
                        .font(.system(size: min(12, geometry.size.width * 0.03), weight: .medium))
                        .foregroundColor(BananaTheme.ColorToken.secondaryText.opacity(0.7))
                }
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func startAnimations() {
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            heroScale = 1.05
        }
        
        withAnimation(.linear(duration: 8.0).repeatForever(autoreverses: false)) {
            starRotation = 360
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
                animationTrigger.toggle()
            }
        }
    }
    
    private func fetchProductsIfNeeded() {
        if purchaseManager.availableProducts.isEmpty && !purchaseManager.isLoadingProducts {
            Task {
                do {
                    try await purchaseManager.fetchProductsForDisplay()
                    
                    // Set default selection to monthly if available
                    if getProduct(for: "daystart_monthly_subscription") != nil {
                        selectedProductID = "daystart_monthly_subscription"
                    } else if let firstProduct = purchaseManager.availableProducts.first {
                        selectedProductID = firstProduct.id
                    }
                } catch {
                    logger.logError(error, context: "Failed to fetch products for paywall")
                }
            }
        }
    }
    
    private func getProduct(for id: String) -> Product? {
        return purchaseManager.availableProducts.first { $0.id == id }
    }
    
    private func getSelectedProduct() -> Product? {
        return getProduct(for: selectedProductID)
    }
    
    private func getPurchaseButtonText() -> String {
        guard let product = getSelectedProduct() else {
            return "Continue"
        }
        
        if let trialText = purchaseManager.getTrialText(for: product) {
            return "Start \(trialText)"
        } else {
            return "Subscribe for \(product.displayPrice)"
        }
    }
    
    private func getPurchaseButtonSubtext(for product: Product) -> String {
        guard let subscription = product.subscription else {
            return ""
        }
        
        if let trialText = purchaseManager.getTrialText(for: product) {
            return "Then \(product.displayPrice) per \(subscription.subscriptionPeriod.unit.localizedDescription.lowercased())"
        } else {
            return "Auto renews \(subscription.subscriptionPeriod.unit.adverbForm)"
        }
    }
    
    private func getSavingsText(annual: Product?, monthly: Product?) -> String? {
        return purchaseManager.getSavingsText(annual: annual, monthly: monthly)
    }
    
    private func startPurchaseFlow() {
        guard !isLoading else { return }
        
        isLoading = true
        logger.log("🛒 Starting purchase flow for product: \(selectedProductID)", level: .info)
        
        Task {
            do {
                try await purchaseManager.purchase(productId: selectedProductID)
                
                await MainActor.run {
                    logger.log("✅ Purchase completed successfully", level: .info)
                    onPurchaseComplete?()
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    logger.logError(error, context: "Purchase failed")

                    if let purchaseError = error as? PurchaseError {
                        switch purchaseError {
                        case .purchaseFailed(let message):
                            errorMessage = message.contains("cancelled") ?
                                "Purchase was cancelled." :
                                "Purchase failed. Please try again."
                        case .keychainStorageFailed(let message):
                            // Special handling for storage failures
                            errorMessage = "Purchase couldn't be saved securely. Please try again or contact support if you were charged."
                            logger.log("🚨 CRITICAL: Purchase storage failed: \(message)", level: .error)
                        case .restoreFailed:
                            errorMessage = "Unable to restore purchases. Please try again."
                        case .receiptNotFound:
                            errorMessage = "No previous purchase found."
                        case .networkError:
                            errorMessage = "Network error. Please check your connection."
                        case .productNotFound:
                            errorMessage = "Product not available. Please try again later."
                        }
                    } else {
                        errorMessage = "Unable to complete purchase. Please check your connection and try again."
                    }
                    showingError = true
                }
            }
        }
    }
    
    private func restorePurchases() async {
        logger.log("🔄 Restoring purchases", level: .info)
        
        do {
            try await purchaseManager.restorePurchases()
            logger.log("✅ Purchases restored successfully", level: .info)
            
            if purchaseManager.isPremium {
                onPurchaseComplete?()
                dismiss()
            }
        } catch {
            logger.logError(error, context: "Failed to restore purchases")
            errorMessage = "Unable to restore purchases. Please try again."
            showingError = true
        }
    }
    
    private func impactFeedback() {
        let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
        impactFeedback.impactOccurred()
    }
}

// MARK: - Supporting Views

struct SubscriptionPlanCard: View {
    let product: Product
    let title: String
    let badge: String?
    let badgeColor: Color
    let isSelected: Bool
    let geometry: GeometryProxy
    let purchaseManager: PurchaseManager
    let animationTrigger: Bool
    let savings: String?
    let weeklyProduct: Product?
    let trialText: String?
    let onTap: () -> Void
    
    init(
        product: Product,
        title: String,
        badge: String? = nil,
        badgeColor: Color = .clear,
        isSelected: Bool,
        geometry: GeometryProxy,
        purchaseManager: PurchaseManager,
        animationTrigger: Bool,
        savings: String? = nil,
        weeklyProduct: Product? = nil,
        trialText: String? = nil,
        onTap: @escaping () -> Void
    ) {
        self.product = product
        self.title = title
        self.badge = badge
        self.badgeColor = badgeColor
        self.isSelected = isSelected
        self.geometry = geometry
        self.purchaseManager = purchaseManager
        self.animationTrigger = animationTrigger
        self.savings = savings
        self.weeklyProduct = weeklyProduct
        self.trialText = trialText
        self.onTap = onTap
    }
    
    // Helper computed properties
    private var hasBottomBadges: Bool {
        purchaseManager.getPromotionalPrice(for: product) != nil ||
        savings != nil
    }
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                // Main card content
                HStack(spacing: 12) {
                // Left side - Title, price, and badge
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(BananaTheme.ColorToken.text)
                            .layoutPriority(1)
                            .fixedSize(horizontal: true, vertical: false)
                        
                        if let badge = badge {
                            Text(badge)
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .frame(minWidth: 100)
                                .background(badgeColor)
                                .cornerRadius(8)
                                .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                    
                    // Time frame and price display with promotional handling
                    if let (promotional, _) = purchaseManager.getPromotionalPrice(for: product) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promotional.formatted(.currency(code: product.priceFormatStyle.currencyCode)))
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            
                            Text(product.displayPrice)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.gray)
                                .strikethrough()
                        }
                    } else {
                        Text(getTimeFrameAndPrice(for: product, title: title))
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            .minimumScaleFactor(0.8)
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    
                }
                
                Spacer()
                
                // Right side - Price
                VStack(alignment: .trailing, spacing: 2) {
                    // Price with promotional handling
                    if let (promotional, savingsPercent) = purchaseManager.getPromotionalPrice(for: product) {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(product.displayPrice)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(BananaTheme.ColorToken.secondaryText)
                                .strikethrough()
                            
                            HStack(spacing: 4) {
                                Text("\(savingsPercent)% OFF")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.red)
                                    .cornerRadius(3)
                                
                                Text(promotional.formatted(.currency(code: product.priceFormatStyle.currencyCode)))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(BananaTheme.ColorToken.text)
                            }
                        }
                    } else {
                        // Show monthly equivalent for annual plan
                        if title == "Annual" {
                            let monthlyEquivalent = product.price / 12
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(monthlyEquivalent.formatted(.currency(code: product.priceFormatStyle.currencyCode)))
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(BananaTheme.ColorToken.text)
                                
                                Text("per month")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            }
                        } else if title == "Monthly" {
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(product.displayPrice)
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundColor(BananaTheme.ColorToken.text)
                                
                                Text("per month")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            }
                        } else {
                            // Weekly plan
                            Text(product.displayPrice)
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(BananaTheme.ColorToken.text)
                            
                            if let subscription = product.subscription {
                                Text("per \(subscription.subscriptionPeriod.unit.localizedDescription.lowercased())")
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(BananaTheme.ColorToken.secondaryText)
                            }
                        }
                    }
                }
                .frame(minHeight: 50, alignment: .center)
                
                // Selection indicator
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundColor(isSelected ? BananaTheme.ColorToken.primary : BananaTheme.ColorToken.border)
                }
                .frame(minHeight: 60, maxHeight: 60)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                
                // Trial text footer
                if let trialText = trialText {
                    HStack {
                        Text(trialText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        UnevenRoundedRectangle(
                            cornerRadii: .init(
                                topLeading: 0,
                                bottomLeading: BananaTheme.CornerRadius.md,
                                bottomTrailing: BananaTheme.CornerRadius.md,
                                topTrailing: 0
                            )
                        )
                        .fill(Color(red: 0.29, green: 0.33, blue: 0.41))
                    )
                }
            }
            .background(
                ZStack {
                    if isSelected {
                        // Selected state: primary color background with reduced opacity
                        RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                            .fill(BananaTheme.ColorToken.primary.opacity(0.1))
                    } else {
                        // Standard card background
                        RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                            .fill(BananaTheme.ColorToken.card)
                    }
                    
                    // Border for selected state
                    if isSelected {
                        RoundedRectangle(cornerRadius: BananaTheme.CornerRadius.md)
                            .stroke(BananaTheme.ColorToken.primary, lineWidth: 2)
                    }
                }
            )
            .shadow(
                color: isSelected ? BananaTheme.ColorToken.primary.opacity(0.2) : BananaTheme.ColorToken.shadow,
                radius: isSelected ? 6 : BananaTheme.Shadow.md.radius,
                x: isSelected ? 0 : BananaTheme.Shadow.md.x,
                y: isSelected ? 3 : BananaTheme.Shadow.md.y
            )
            .overlay(
                // Top-right savings badge
                VStack {
                    HStack {
                        Spacer()
                        // Show weekly savings badge for monthly/annual plans
                        if let weeklySavings = purchaseManager.getWeeklySavings(for: product, weeklyProduct: weeklyProduct) {
                            Text("Save \(weeklySavings.percentage)%")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(weeklySavings.color)
                                )
                        } else if let savings = savings {
                            // Fallback to original savings display (annual vs monthly)
                            Text(savings)
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.green)
                                )
                        }
                    }
                    Spacer()
                }
                .padding(.top, -8)
                .padding(.trailing, -8)
            )
            .overlay(
                // Bottom badges overlay
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        
                        // Promotional badge at bottom-right
                        if let (_, savingsPercent) = purchaseManager.getPromotionalPrice(for: product) {
                            Text("🔥 \(savingsPercent)% OFF")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color.red)
                                )
                        }
                    }
                }
                .padding(.bottom, 8)
                .padding(.horizontal, 16)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isSelected)
        .scaleEffect(isSelected ? (animationTrigger ? 1.03 : 1.02) : 1.0)
        .animation(
            isSelected ? .easeInOut(duration: 2.0).repeatForever(autoreverses: true) : .default,
            value: animationTrigger
        )
    }
    
    // Helper function to get time frame and price text
    private func getTimeFrameAndPrice(for product: Product, title: String) -> String {
        switch title {
        case "Weekly":
            return "1 wk • \(product.displayPrice)"
        case "Monthly":
            return "1 mo • \(product.displayPrice)"
        case "Annual":
            return "12 mos • \(product.displayPrice)"
        default:
            return product.displayPrice
        }
    }
}


// MARK: - Extensions

extension StoreKit.Product.SubscriptionPeriod.Unit {
    var localizedDescription: String {
        switch self {
        case .day:
            return "Day"
        case .week:
            return "Week"
        case .month:
            return "Month"
        case .year:
            return "Year"
        @unknown default:
            return "Period"
        }
    }
    
    var adverbForm: String {
        switch self {
        case .day:
            return "daily"
        case .week:
            return "weekly"
        case .month:
            return "monthly"
        case .year:
            return "yearly"
        @unknown default:
            return "periodically"
        }
    }
}


// MARK: - Preview

struct PaywallView_Previews: PreviewProvider {
    static var previews: some View {
        PaywallView()
    }
}