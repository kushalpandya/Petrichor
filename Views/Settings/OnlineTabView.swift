import SwiftUI

struct OnlineTabView: View {
    @AppStorage("lastfmUsername")
    private var lastfmUsername: String = ""
    
    @AppStorage("scrobblingEnabled")
    private var scrobblingEnabled: Bool = true
    
    @AppStorage("loveSyncEnabled")
    private var loveSyncEnabled: Bool = true
    
    @AppStorage("onlineLyricsEnabled")
    private var onlineLyricsEnabled: Bool = false
    
    @State private var isAuthenticating = false
    @State private var showLoveSyncInfo = false
    @State private var showDisconnectConfirmation = false
    
    private var isConnected: Bool {
        !lastfmUsername.isEmpty
    }
    
    private var cachedLastFMAvatar: NSImage? {
        guard let data = UserDefaults.standard.data(forKey: "lastfmAvatarData"),
              let image = NSImage(data: data) else {
            return nil
        }
        return image
    }
    
    var body: some View {
        Form {
            Section {
                lastfmSection
            } header: {
                Text("Last.fm")
            }
            
            Section {
                lyricsSection
            } header: {
                Text("Lyrics")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .padding(5)
        .alert("Disconnect from Last.fm?", isPresented: $showDisconnectConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Disconnect", role: .destructive) {
                disconnect()
            }
        } message: {
            Text("Your listening activity will no longer be scrobbled to Last.fm once you disconnect.")
        }
    }
    
    // MARK: - Last.fm Section
    
    @ViewBuilder
    private var lastfmSection: some View {
        if isConnected {
            connectedView
        } else {
            disconnectedView
        }
    }
    
    private var connectedView: some View {
        Group {
            HStack {
                Group {
                    if let avatar = cachedLastFMAvatar {
                        Image(nsImage: avatar)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: Icons.personFill)
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(lastfmUsername)
                        .font(.system(size: 13, weight: .medium))
                    Text("Connected")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                }
                
                Spacer()
                
                Button {
                    showDisconnectConfirmation = true
                } label: {
                    Text("Disconnect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .background(Color.red)
                .cornerRadius(5)
            }
            .padding(.vertical, 4)
            
            Toggle("Enable scrobbling", isOn: $scrobblingEnabled)
                .help("Track your listening history on Last.fm")
            
            Toggle(isOn: $loveSyncEnabled) {
                HStack(spacing: 4) {
                    Text("Sync favorites as Loved tracks")
                    
                    Button {
                        showLoveSyncInfo.toggle()
                    } label: {
                        Image(systemName: "questionmark.circle")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showLoveSyncInfo, arrowEdge: .trailing) {
                        Text("Tracks you favorite in Petrichor will be loved on Last.fm. Loved tracks on Last.fm won't sync back to Petrichor.")
                            .font(.system(size: 12))
                            .padding(10)
                            .frame(width: 220)
                    }
                }
            }
        }
    }
    
    private var disconnectedView: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Not connected")
                    .font(.system(size: 13, weight: .medium))
                Text("Connect your Last.fm account to start scrobbling")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: startAuthentication) {
                if isAuthenticating {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 60)
                } else {
                    Text("Connect")
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(isAuthenticating)
        }
        .padding(.vertical, 4)
    }
    
    // MARK: - Lyrics Section
            
    private var lyricsSection: some View {
        Toggle("Fetch lyrics from internet when unavailable", isOn: $onlineLyricsEnabled)
            .help("Automatically search for lyrics online when no local lyrics are found")
    }
    
    // MARK: - Actions
    
    private func startAuthentication() {
        guard let scrobbleManager = AppCoordinator.shared?.scrobbleManager,
              let authURL = scrobbleManager.authenticationURL() else {
            return
        }
        
        isAuthenticating = true
        NSWorkspace.shared.open(authURL)
        Logger.info("Opened Last.fm authorization page")
        
        // Reset authenticating state after a delay
        // The actual authentication will complete via URL scheme callback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isAuthenticating = false
        }
    }
    
    private func disconnect() {
        lastfmUsername = ""
        scrobblingEnabled = true
        loveSyncEnabled = true
        
        // Clear cached avatar
        UserDefaults.standard.removeObject(forKey: "lastfmAvatarData")
        
        // Clear session from Keychain
        KeychainManager.delete(key: KeychainManager.Keys.lastfmSessionKey)
        
        Logger.info("Disconnected from Last.fm")
        NotificationManager.shared.addMessage(.info, "Disconnected from Last.fm")
    }
}

#Preview {
    OnlineTabView()
        .frame(width: 600, height: 400)
}
