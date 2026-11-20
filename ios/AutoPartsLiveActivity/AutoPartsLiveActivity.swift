import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivitiesAppAttributes: ActivityAttributes, Identifiable {
    public typealias LiveDeliveryData = ContentState
    public struct ContentState: Codable, Hashable {}
    var id = UUID()
}

extension LiveActivitiesAppAttributes {
    func prefixedKey(_ key: String) -> String {
        return "\(id)_\(key)"
    }
}

private let sharedDefault = UserDefaults(suiteName: "group.com.autoparts.app")

@main
struct AutoPartsLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        AutoPartsLiveActivityWidget()
    }
}

struct AutoPartsLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LiveActivitiesAppAttributes.self) { context in
            let title = sharedDefault?.string(forKey: context.attributes.prefixedKey("title")) ?? "أوتو بارتس برو"
            let status = sharedDefault?.string(forKey: context.attributes.prefixedKey("statusText")) ?? "جاري المتابعة..."
            let rawProgress = sharedDefault?.double(forKey: context.attributes.prefixedKey("progress")) ?? 0.1
            let progress = min(max(rawProgress, 0.0), 1.0)
            let eta = sharedDefault?.string(forKey: context.attributes.prefixedKey("etaOrDistance")) ?? ""

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "car.fill")
                        .foregroundColor(.orange)
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.white)
                    Spacer()
                    if !eta.isEmpty {
                        Text(eta)
                            .font(.caption.bold())
                            .foregroundColor(.orange)
                    }
                }
                Text(status)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.85))
                ProgressView(value: progress)
                    .tint(.orange)
            }
            .padding()
            .background(Color(red: 0.067, green: 0.114, blue: 0.169))

        } dynamicIsland: { context in
            let title = sharedDefault?.string(forKey: context.attributes.prefixedKey("title")) ?? "أوتو بارتس"
            let status = sharedDefault?.string(forKey: context.attributes.prefixedKey("statusText")) ?? ""
            let rawProgress = sharedDefault?.double(forKey: context.attributes.prefixedKey("progress")) ?? 0.1
            let progress = min(max(rawProgress, 0.0), 1.0)
            let eta = sharedDefault?.string(forKey: context.attributes.prefixedKey("etaOrDistance")) ?? ""

            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "wrench.and.screwdriver.fill")
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(Int(progress * 100))%")
                        .font(.headline)
                        .foregroundColor(.orange)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title).font(.caption.bold()).foregroundColor(.white)
                        Text(status).font(.caption2).foregroundColor(.white.opacity(0.8))
                        ProgressView(value: progress).tint(.orange)
                    }
                }
            } compactLeading: {
                Image(systemName: "car.fill")
                    .foregroundColor(.orange)
            } compactTrailing: {
                Text(eta.isEmpty ? "\(Int(progress * 100))%" : eta)
                    .font(.caption2.bold())
                    .foregroundColor(.orange)
            } minimal: {
                Image(systemName: "car.fill")
                    .foregroundColor(.orange)
            }
        }
    }
}