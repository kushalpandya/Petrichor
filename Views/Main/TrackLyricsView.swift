import SwiftUI

struct TrackLyricsView: View {
    let track: Track
    let onClose: () -> Void
    
    @EnvironmentObject var libraryManager: LibraryManager
    
    @State private var lyrics: String = ""
    @State private var isLoading = true
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            
            Divider()
            
            // Lyrics content
            if isLoading {
                loadingView
            } else if lyrics.isEmpty {
                emptyLyricsView
            } else {
                lyricsContent
            }
        }
        .onAppear {
            loadLyrics()
        }
    }
    
    // MARK: - Header
    
    private var header: some View {
        ListHeader {
            HStack(spacing: 12) {
                Button(action: onClose) {
                    Image(systemName: Icons.xmarkCircleFill)
                        .font(.system(size: 16))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                
                Text("Lyrics")
                    .headerTitleStyle()
            }
            
            Spacer()
        }
    }
    
    // MARK: - Loading View
    
    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Loading lyrics...")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Empty Lyrics View
    
    private var emptyLyricsView: some View {
        VStack(spacing: 16) {
            Image(Icons.customLyrics)
                .font(.system(size: 48))
                .foregroundColor(.gray)
            
            Text("No Lyrics Available")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    // MARK: - Lyrics Content
    
    private var lyricsContent: some View {
        ScrollView {
            Text(lyrics)
                .font(.system(size: 14))
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
                .lineSpacing(10)
                .padding(20)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Helper Methods
    
    private func loadLyrics() {
        Task {
            do {
                let result = try await LyricsLoader.loadLyrics(
                    for: track,
                    using: libraryManager.databaseManager.dbQueue
                )
                
                await MainActor.run {
                    lyrics = result.lyrics
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    lyrics = ""
                    isLoading = false
                }
            }
        }
    }
}
