import SwiftUI

// MARK: - Notification Types

enum NotificationType {
    case info
    case warning
    case error
    
    var icon: String {
        switch self {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .info: return .accentColor
        case .warning: return .orange
        case .error: return .red
        }
    }
}

struct NotificationMessage: Identifiable {
    let id = UUID()
    let type: NotificationType
    let title: String
    let timestamp: Date
    
    init(type: NotificationType, title: String) {
        self.type = type
        self.title = title
        self.timestamp = Date()
    }
}

// MARK: - Notification Manager

class NotificationManager: ObservableObject {
    static let shared = NotificationManager()
    
    @Published var isActivityInProgress = false
    @Published var activityMessage = ""
    @Published var messages: [NotificationMessage] = []
    
    private let messagesKey = "NotificationTrayMessages"
    
    private init() {
        loadPersistedMessages()
    }
    
    // MARK: - Activity Management
    
    func startActivity(_ message: String) {
        DispatchQueue.main.async {
            self.isActivityInProgress = true
            self.activityMessage = message
        }
    }
    
    func stopActivity() {
        DispatchQueue.main.async {
            self.isActivityInProgress = false
            self.activityMessage = ""
        }
    }
    
    // MARK: - Message Management
    
    func addMessage(_ type: NotificationType, _ title: String) {
        DispatchQueue.main.async {
            let message = NotificationMessage(type: type, title: title)
            self.messages.append(message)
            self.saveMessages()
        }
    }
    
    func clearMessages() {
        DispatchQueue.main.async {
            self.messages.removeAll()
            self.saveMessages()
        }
    }
    
    func removeMessage(_ message: NotificationMessage) {
        DispatchQueue.main.async {
            self.messages.removeAll { $0.id == message.id }
            self.saveMessages()
        }
    }
    
    // MARK: - Persistence
    
    private func saveMessages() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        if let encoded = try? encoder.encode(messages) {
            UserDefaults.standard.set(encoded, forKey: messagesKey)
        }
    }
    
    private func loadPersistedMessages() {
        guard let data = UserDefaults.standard.data(forKey: messagesKey) else { return }
        
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        if let decoded = try? decoder.decode([NotificationMessage].self, from: data) {
            messages = decoded
        }
    }
}

// Make NotificationMessage conform to Codable for persistence
extension NotificationMessage: Codable {
    enum CodingKeys: String, CodingKey {
        case type, title, timestamp
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encode(timestamp, forKey: .timestamp)
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.type = try container.decode(NotificationType.self, forKey: .type)
        self.title = try container.decode(String.self, forKey: .title)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
    }
}

extension NotificationType: Codable {}

// MARK: - Notification Tray View

struct NotificationTray: View {
    @StateObject private var manager = NotificationManager.shared
    @State private var showingPopover = false
    @State private var isHovered = false
    @State private var showingActivity = false
    
    var body: some View {
        Button(action: {
            if hasNotifications {
                showingPopover.toggle()
            }
        }) {
            ZStack {
                // Background circle only on hover
                if isHovered {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 24, height: 24)
                        .animation(.easeInOut(duration: 0.1), value: isHovered)
                }
                
                if showingActivity {
                    // Activity indicator
                    activityIndicator
                } else if hasNotifications {
                    // Notification icon
                    Image(systemName: mostSevereNotificationType.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(mostSevereNotificationType.color)
                        .frame(width: 24, height: 24)
                }
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            NotificationPopover(isPresented: $showingPopover)
        }
        .help(tooltipText)
        .onHover { hovering in
            isHovered = hovering
        }
        .onChange(of: manager.isActivityInProgress) { _, newValue in
            if newValue {
                showingActivity = true
            } else {
                // Delay hiding activity to prevent flicker
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    showingActivity = false
                }
            }
        }
        .transition(.scale.combined(with: .opacity))
    }
    
    // MARK: - Computed Properties
    
    private var hasNotifications: Bool {
        !manager.messages.isEmpty
    }
    
    private var mostSevereNotificationType: NotificationType {
        if manager.messages.contains(where: { $0.type == .error }) {
            return .error
        } else if manager.messages.contains(where: { $0.type == .warning }) {
            return .warning
        }
        return .info
    }
    
    private var tooltipText: String {
        if manager.isActivityInProgress {
            return manager.activityMessage.isEmpty ? "Refreshing Library..." : manager.activityMessage
        } else if hasNotifications {
            return "\(manager.messages.count) notification\(manager.messages.count == 1 ? "" : "s")"
        }
        return ""
    }
    
    // MARK: - Activity Indicator
    
    @ViewBuilder
    private var activityIndicator: some View {
        ActivityAnimation(size: .small)
            .frame(width: 25, height: 25)
    }
}

// MARK: - Notification Popover

struct NotificationPopover: View {
    @StateObject private var manager = NotificationManager.shared
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Notifications")
                    .font(.headline)
                
                Spacer()
                
                if !manager.messages.isEmpty {
                    Button("Clear") {
                        manager.clearMessages()
                        isPresented = false
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("Clear all notifications")
                }
            }
            .padding(10)
            
            Divider()
            
            // Messages
            if manager.messages.isEmpty {
                emptyState
            } else {
                messagesList
            }
        }
        .frame(width: 350)
        .frame(maxHeight: 400)
    }
    
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "bell.slash")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            
            Text("No notifications")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
    
    @ViewBuilder
    private var messagesList: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(manager.messages.reversed()) { message in
                    NotificationRow(message: message) {
                        manager.removeMessage(message)
                    }
                    
                    if message.id != manager.messages.first?.id {
                        Divider()
                            .padding(.horizontal)
                    }
                }
            }
        }
    }
}

// MARK: - Notification Row

struct NotificationRow: View {
    let message: NotificationMessage
    let onDismiss: () -> Void
    
    @State private var isHovered = false
    
    private var timeAgoText: String {
        let now = Date()
        let interval = now.timeIntervalSince(message.timestamp)
        
        if interval < 60 {
            return "Just now"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes) min\(minutes == 1 ? "" : "s") ago"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours) hour\(hours == 1 ? "" : "s") ago"
        } else {
            let days = Int(interval / 86400)
            return "\(days) day\(days == 1 ? "" : "s") ago"
        }
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: message.type.icon)
                .font(.system(size: 14))
                .foregroundColor(message.type.color)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(message.title)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                
                Text(timeAgoText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            if isHovered {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 40) {
        // Activity in progress
        NotificationTray()
            .onAppear {
                NotificationManager.shared.startActivity("Scanning for new music...")
            }
        
        // With notifications
        NotificationTray()
            .onAppear {
                NotificationManager.shared.stopActivity()
                NotificationManager.shared.addMessage(.info, "2 folders refreshed for changes")
                NotificationManager.shared.addMessage(.warning, "1 folder couldn't be accessed")
                NotificationManager.shared.addMessage(.error, "Failed to scan Downloads folder")
            }
    }
    .padding()
}
