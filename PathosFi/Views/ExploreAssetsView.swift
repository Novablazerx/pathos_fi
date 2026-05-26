import SwiftUI

struct ExploreAssetsView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedCategory: AssetCategory? = nil
    @State private var searchText = ""
    @State private var selectedAsset: AssetInfo? = nil

    private var allAssets: [AssetInfo] {
        appState.backendAssets.sorted { $0.ticker < $1.ticker }
    }

    private var filteredAssets: [AssetInfo] {
        allAssets.filter { asset in
            let categoryMatch = selectedCategory == nil || asset.category == selectedCategory
            let searchMatch = searchText.isEmpty ||
                asset.ticker.localizedCaseInsensitiveContains(searchText) ||
                asset.name.localizedCaseInsensitiveContains(searchText)
            return categoryMatch && searchMatch
        }
    }

    private var groupedAssets: [(category: AssetCategory, assets: [AssetInfo])] {
        let order: [AssetCategory] = [.equity, .bond, .commodity, .inverseEquity, .option]
        return order.compactMap { cat in
            let assets = filteredAssets.filter { $0.category == cat }
            return assets.isEmpty ? nil : (cat, assets)
        }
    }

    var body: some View {
        ZStack {
            AuraBackground()

            VStack(spacing: 0) {
                ExploreHeaderView(
                    onBack: { appState.navigateBack() },
                    count: filteredAssets.count
                )

                CategoryFilterBar(selected: $selectedCategory)
                    .padding(.bottom, 8)

                SearchBarView(text: $searchText)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                if appState.backendAssets.isEmpty {
                    Spacer()
                    VStack(spacing: 12) {
                        ProgressView().tint(Color.teal)
                        Text("Loading assets…")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                            ForEach(groupedAssets, id: \.category) { group in
                                Section {
                                    VStack(spacing: 10) {
                                        ForEach(group.assets) { asset in
                                            Button { selectedAsset = asset } label: {
                                                AssetMarketplaceRow(asset: asset)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal, 16)
                                    .padding(.bottom, 16)
                                } header: {
                                    AssetSectionHeader(category: group.category, count: group.assets.count)
                                }
                            }
                            Spacer(minLength: 40)
                        }
                    }
                }
            }
            .fullScreenCover(item: $selectedAsset) { asset in
                AssetDetailsView(asset: asset)
                    .environmentObject(appState)
            }
        }
    }
}

// MARK: - Header

private struct ExploreHeaderView: View {
    let onBack: () -> Void
    let count: Int

    var body: some View {
        HStack(alignment: .center) {
            Button(action: onBack) {
                ZStack {
                    Circle()
                        .fill(Color(white: 0.12))
                        .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 1))
                        .frame(width: 42, height: 42)
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("MARKETPLACE")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(Color.purple.opacity(0.8))
                    .tracking(2)
                Text("Explore Assets")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
            }
            .padding(.leading, 12)

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(Color.teal)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.teal.opacity(0.12))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Color.teal.opacity(0.3), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }
}

// MARK: - Section Header

private struct AssetSectionHeader: View {
    let category: AssetCategory
    let count: Int

    private var accentColor: Color {
        switch category {
        case .equity:        return Color.teal
        case .bond:          return Color.purple
        case .commodity:     return Color.orange
        case .inverseEquity: return Color.pink
        case .option:        return Color.indigo
        }
    }

    private var icon: String {
        switch category {
        case .equity:        return "chart.line.uptrend.xyaxis"
        case .bond:          return "building.columns"
        case .commodity:     return "cube.fill"
        case .inverseEquity: return "arrow.down.right"
        case .option:        return "doc.plaintext"
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor)
            Text(category.rawValue.uppercased())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(accentColor)
                .tracking(1.5)
            Spacer()
            Text("\(count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(accentColor.opacity(0.6))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color(red: 0.039, green: 0.027, blue: 0.063).opacity(0.95)
                .background(.ultraThinMaterial)
        )
    }
}

// MARK: - Category Filter Bar

private struct CategoryFilterBar: View {
    @Binding var selected: AssetCategory?

    private let categories: [(label: String, value: AssetCategory?)] = [
        ("All", nil),
        ("Equity", .equity),
        ("Bond", .bond),
        ("Commodity", .commodity),
        ("Inverse", .inverseEquity),
        ("Option", .option),
    ]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(categories, id: \.label) { item in
                    let isSelected = selected == item.value
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selected = item.value
                        }
                    } label: {
                        Text(item.label)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(isSelected ? Color(red: 0.039, green: 0.027, blue: 0.063) : .white.opacity(0.6))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(isSelected ? Color.teal : Color.white.opacity(0.06))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(isSelected ? Color.clear : .white.opacity(0.1), lineWidth: 1))
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Search Bar

private struct SearchBarView: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.4))
            TextField("Search ticker or name…", text: $text)
                .font(.system(size: 14))
                .foregroundStyle(.white)
                .tint(Color.teal)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

// MARK: - Asset Row

private struct AssetMarketplaceRow: View {
    let asset: AssetInfo

    private var accentColor: Color {
        switch asset.category {
        case .equity:        return Color.teal
        case .bond:          return Color.purple
        case .commodity:     return Color.orange
        case .inverseEquity: return Color.pink
        case .option:        return Color.indigo
        }
    }

    private var dayChangeStr: String {
        let pct = asset.dayChangePercent
        return (pct >= 0 ? "+" : "") + String(format: "%.1f", pct) + "%"
    }

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(accentColor.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(accentColor.opacity(0.25), lineWidth: 1))
                    .frame(width: 48, height: 48)
                Text(asset.ticker.prefix(3))
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(asset.ticker)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Text(asset.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
            }

            Spacer()

            Text(dayChangeStr)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(asset.dayChangePercent >= 0 ? Color.teal : Color.pink)

            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.teal.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.teal.opacity(0.3), lineWidth: 1))
                    .frame(width: 36, height: 36)
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.teal)
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 20)
    }
}

#Preview {
    ExploreAssetsView()
        .environmentObject(AppState())
}
