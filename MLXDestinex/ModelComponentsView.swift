import Hub  // Import the Hub module
import OSLog  // Use Apple's unified logging
import SwiftUI

// Represents a file fetched/downloaded from the Hub, categorized for display
struct HubFileDisplay: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let category: FileCategory
    let size: String
    let url: URL?  // Local URL after download
    
    enum FileCategory: String, CaseIterable, Comparable {
        case Config
        case Tokenizer
        case Weights
        case Other
        
        // Define comparison logic for sorting
        static func < (lhs: HubFileDisplay.FileCategory, rhs: HubFileDisplay.FileCategory) -> Bool {
            func order(_ category: FileCategory) -> Int {
                switch category {
                case .Config: return 1
                case .Tokenizer: return 2
                case .Weights: return 3
                case .Other: return 4
                }
            }
            return order(lhs) < order(rhs)
        }
    }
    
    // Helper to format bytes into readable string
    static func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "N/A" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    // Determine category based on filename - refined based on screenshot
    static func categorize(filename: String) -> FileCategory {
        if filename == "config.json" || filename == "generation_config.json" {
            return .Config
        } else if filename == "tokenizer.json" || filename == "tokenizer_config.json"
                    || filename == "special_tokens_map.json" || filename == "vocab.json"
                    || filename == "merges.txt" || filename == "added_tokens.json"
        {
            return .Tokenizer
        } else if filename.hasSuffix(".safetensors") || filename.hasSuffix(".safetensors.index.json") {
            return .Weights
        } else {
            return .Other  // README.md, .gitattributes, etc.
        }
    }
    
    // Implement Hashable
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: HubFileDisplay, rhs: HubFileDisplay) -> Bool {
        lhs.id == rhs.id
    }
}

struct ModelComponentsView: View {
    let modelId: String
    
    @State private var filesByCategory: [HubFileDisplay.FileCategory: [HubFileDisplay]] = [:]
    @State private var downloadState: LoadState = .idle  // Uses the modified LoadState enum
    
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "ModelComponentsView", category: "HubLoading")
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Components for model: **\(modelId)**")
                        .font(.headline)
                        .padding(.bottom, 5)
                    
                        .font(.callout)
                } header: {
                    Text("Model Anatomy")
                }
                
                Section {
                    switch downloadState {
                    case .idle:
                        Button("Download Model Files") {
                            Task { await downloadAndListModelFiles() }
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                    case .loading:
                        HStack {
                            Spacer()
                            ProgressView("Preparing Download...")
                            Spacer()
                        }
                    case .downloading(let progress):
                        VStack(spacing: 4) {
                            ProgressView(value: progress.fractionCompleted)
                                .progressViewStyle(.linear)
                                .frame(maxWidth: 200)
                            Text("Downloading: \(Int(progress.fractionCompleted * 100))%")
                                .foregroundColor(.secondary)
                        }
                    case .ready:
                        Text("Files Downloaded/Verified in Cache")
                            .foregroundColor(.green)
                            .frame(maxWidth: .infinity, alignment: .center)
                    case .error(let error):
                        Text("Error: \(error.localizedDescription)")
                            .foregroundColor(.red)
                    }
                }
                
                if case .ready = downloadState {
                    ForEach(
                        HubFileDisplay.FileCategory.allCases.filter { filesByCategory.keys.contains($0) },
                        id: \.self
                    ) { category in
                        displaySection(category: category)
                    }
                }
                
            }
            .listStyle(InsetGroupedListStyle())
            .navigationTitle("Model Files")
            .refreshable {
                await downloadAndListModelFiles()
            }
        }
    }
    
    @ViewBuilder
    private func displaySection(category: HubFileDisplay.FileCategory) -> some View {
        if let categoryFiles = filesByCategory[category], !categoryFiles.isEmpty {
            Section {
                FileGroupView(
                    icon: icon(for: category),
                    title: title(for: category),
                    files: categoryFiles
                )
            } header: {
                Text("\(title(for: category))")
            }
        }
    }
    
    private func downloadAndListModelFiles() async {
        guard downloadState != .loading && !isDownloading() else { return }
        
        await MainActor.run { downloadState = .loading }
        filesByCategory = [:]
        
        let hubApi = HubApi()
        let repo = Hub.Repo(id: modelId)
        let essentialGlobs = ["*.json", "*.safetensors", "*.txt"]
        Self.logger.info("Starting snapshot download for model: \(self.modelId)")
        
        do {
            let snapshotURL = try await hubApi.snapshot(from: repo, matching: essentialGlobs) {
                progress in
                Task { @MainActor in
                    let fraction = progress.fractionCompleted
                    let description = progress.localizedDescription  // Can be nil
                    self.downloadState = .downloading(progress)
                    Self.logger.debug(
                        "Download progress: \(fraction * 100)% (\(description ?? "No description"))")
                }
            }
            Self.logger.info("Snapshot download/verification complete. Local path: \(snapshotURL.path)")
            
            let fileManager = FileManager.default
            guard
                let enumerator = fileManager.enumerator(
                    at: snapshotURL, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsPackageDescendants])
            else {
                throw NSError(
                    domain: "ModelComponentsView", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to enumerate files in snapshot directory."])
            }
            
            var groupedFiles = [HubFileDisplay.FileCategory: [HubFileDisplay]]()
            for case let fileURL as URL in enumerator {
                let resourceKeys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
                let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
                if resourceValues.isRegularFile ?? false {
                    let filename = fileURL.lastPathComponent
                    let category = HubFileDisplay.categorize(filename: filename)
                    let fileSize = resourceValues.fileSize.map { Int64($0) }
                    
                    let displayFile = HubFileDisplay(
                        name: filename,
                        category: category,
                        size: HubFileDisplay.formatBytes(fileSize),
                        url: fileURL
                    )
                    groupedFiles[category, default: []].append(displayFile)
                }
            }
            
            for category in groupedFiles.keys {
                groupedFiles[category]?.sort { $0.name < $1.name }
            }
            
            await MainActor.run {
                self.filesByCategory = groupedFiles
                self.downloadState = .ready
            }
        } catch let error as Hub.HubClientError {
            await MainActor.run {
                downloadState = .error(error)
            }
            Self.logger.error(
                "Hub Error during snapshot for \(self.modelId): \(error.localizedDescription)")
        } catch {
            await MainActor.run {
                downloadState = .error(error)
            }
            Self.logger.error(
                "Unexpected Error during snapshot for \(self.modelId): \(error.localizedDescription)")
        }
    }
    
    private func isDownloading() -> Bool {
        if case .downloading = downloadState {
            return true
        }
        return false
    }
    
    private func icon(for category: HubFileDisplay.FileCategory) -> String {
        switch category {
        case .Config: return "doc.text.fill"
        case .Tokenizer: return "textformat.abc.dottedunderline"
        case .Weights: return "cpu.fill"  // Or 'memorychip.fill'
        case .Other: return "questionmark.folder.fill"
        }
    }
    
    private func title(for category: HubFileDisplay.FileCategory) -> String {
        switch category {
        case .Config: return "1. Configuration"
        case .Tokenizer: return "2. Tokenizer"
        case .Weights: return "3. Weights"
        case .Other: return "4. Other Files (if present)"  // Clarify 'Other'
        }
    }
}

struct FileGroupView: View {
    let icon: String
    let title: String
    let files: [HubFileDisplay]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading) {
                ForEach(files) { file in
                    HStack {
                        Image(systemName: icon(for: file.category))
                            .foregroundColor(.secondary)
                            .frame(width: 20, alignment: .center)
                        Text(file.name)
                            .font(.caption.monospaced())
                        Spacer()
                        Text(file.size)
                            .font(.caption)
                            .foregroundColor(.gray)
                    }
                    .padding(.leading, 8)
                }
            }
        }
        .padding(.vertical, 5)
    }
    
    private func icon(for category: HubFileDisplay.FileCategory) -> String {
        switch category {
        case .Config: return "doc.text"
        case .Tokenizer: return "textformat.abc"
        case .Weights: return "memorychip"
        case .Other: return "questionmark.folder"
        }
    }
}

struct ModelComponentsView_Previews: PreviewProvider {
    static var previews: some View {
        ModelComponentsView(modelId: "mlx-community/Qwen1.5-0.5B-Chat-4bit")
            .previewDisplayName("Qwen 1.5 0.5B Chat 4bit")
        
        ModelComponentsView(modelId: "google/paligemma-3b-mix-448")
            .previewDisplayName("PaliGemma 3B")
        
        ModelComponentsView(modelId: "non-existent-model-id-12345")
            .previewDisplayName("Error State")
    }
}

extension Substring {
    var string: String { String(self) }
}
