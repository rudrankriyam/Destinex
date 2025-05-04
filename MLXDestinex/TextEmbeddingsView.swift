import MLX
import MLXEmbedders
import SwiftUI
import Tokenizers

struct DocumentResult: Identifiable, Hashable {
  let id = UUID()
  let text: String
  let similarity: Float
}

struct ModelStatusView: View {
  let loadState: LoadState

  var body: some View {
    HStack(spacing: 12) {
      Text("Model Status:")
        .font(.headline)
        .foregroundStyle(.secondary)

      switch loadState {
      case .idle:
        Label("Idle", systemImage: "circle.dashed")
          .foregroundStyle(.gray)
      case .loading:
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text("Loading...")
            .fontWeight(.medium)
        }
        .foregroundStyle(.orange)
      case .downloading(let progress):
        HStack(spacing: 8) {
          ProgressView(value: progress.fractionCompleted)
            .frame(width: 80)
          Text("\(Int(progress.fractionCompleted * 100))%")
            .monospacedDigit()
            .fontWeight(.medium)
        }
        .foregroundStyle(.blue)
      case .ready:
        Label("Ready", systemImage: "checkmark.circle.fill")
          .fontWeight(.medium)
          .foregroundStyle(.green)
      case .error(let error):
        Label("Error", systemImage: "exclamationmark.triangle.fill")
          .fontWeight(.medium)
          .foregroundStyle(.red)
          .help(error.localizedDescription)
      }
      Spacer()
    }
    .padding()
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
    .padding(.horizontal)
    .padding(.bottom, 8)
  }
}

struct InputSectionView: View {
  @Binding var queryText: String
  let documentTexts: [String]
  let isProcessing: Bool
  let isModelReady: Bool
  let findAction: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      VStack(alignment: .leading, spacing: 8) {
        Label("Search Query", systemImage: "magnifyingglass")
          .font(.headline)

        TextField("Enter your search query", text: $queryText, axis: .vertical)
          .textFieldStyle(.roundedBorder)
          .lineLimit(2...)
          .padding(.horizontal, 4)
      }

      VStack(alignment: .leading, spacing: 8) {
        Label("Documents", systemImage: "doc.text")
          .font(.headline)

        VStack(alignment: .leading, spacing: 8) {
          ForEach(documentTexts.indices, id: \.self) { index in
            HStack(alignment: .top, spacing: 8) {
              Text("•")
                .foregroundStyle(.secondary)
              Text(documentTexts[index])
                .font(.subheadline)
                .lineLimit(1)
                .foregroundStyle(.secondary)
            }
          }
        }
        .padding(.leading, 4)
      }

      Button(action: findAction) {
        HStack {
          if isProcessing {
            ProgressView()
              .controlSize(.small)
            Text("Processing...")
          } else {
            Image(systemName: "sparkle.magnifyingglass")
            Text("Find Similar Documents")
          }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.large)
      .disabled(!isModelReady || isProcessing || queryText.isEmpty)
      .animation(.spring(duration: 0.3), value: isProcessing)
    }
    .padding()
    .background(Color(.systemBackground))
    .clipShape(RoundedRectangle(cornerRadius: 12))
    .overlay(
      RoundedRectangle(cornerRadius: 12)
        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
    )
    .padding(.horizontal)
  }
}

struct ResultsSectionView: View {
  let rankedResults: [DocumentResult]
  let isProcessing: Bool
  let processingError: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Results", systemImage: "list.bullet.rectangle")
        .font(.headline)
        .padding(.horizontal)

      if let errorMsg = processingError {
        HStack {
          Image(systemName: "exclamationmark.triangle.fill")
            .foregroundStyle(.red)
          Text(errorMsg)
            .foregroundStyle(.red)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal)
      } else if rankedResults.isEmpty && !isProcessing {
        VStack(spacing: 16) {
          Image(systemName: "text.magnifyingglass")
            .font(.system(size: 32))
            .foregroundStyle(.secondary)
            .padding()

          Text("Enter a query and press 'Find Similar' to see results.")
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
      } else if isProcessing && rankedResults.isEmpty {
        VStack {
          ProgressView("Analyzing documents...")
            .padding()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
      } else {
        ScrollView {
          LazyVStack(spacing: 12) {
            ForEach(rankedResults) { result in
              HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                  Text(result.text)
                    .lineLimit(2)

                  // Similarity bar indicator
                  GeometryReader { geo in
                    ZStack(alignment: .leading) {
                      RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)

                      RoundedRectangle(cornerRadius: 4)
                        .fill(similarityColor(result.similarity))
                        .frame(
                          width: max(10, geo.size.width * CGFloat(result.similarity)), height: 8)
                    }
                  }
                  .frame(height: 8)
                  .padding(.top, 4)
                }

                Spacer()

                Text(String(format: "%.2f", result.similarity))
                  .font(.system(.body, design: .monospaced))
                  .padding(.horizontal, 8)
                  .padding(.vertical, 4)
                  .background(similarityColor(result.similarity).opacity(0.2))
                  .foregroundStyle(similarityColor(result.similarity))
                  .clipShape(RoundedRectangle(cornerRadius: 6))
              }
              .padding()
              .background(Color(.secondarySystemBackground))
              .clipShape(RoundedRectangle(cornerRadius: 12))
            }
          }
          .padding(.horizontal)
          .animation(.spring(duration: 0.3), value: rankedResults)
        }
      }
    }
    .padding(.top, 8)
  }

  private func similarityColor(_ similarity: Float) -> Color {
    if similarity > 0.7 {
      return .green
    } else if similarity > 0.4 {
      return .orange
    } else {
      return .red
    }
  }
}

struct TextEmbeddingsView: View {
  // --- State Variables ---
  @State private var modelContainer: ModelContainer?
  @State private var loadState: LoadState = .idle
  @State private var isProcessing: Bool = false
  @State private var queryText: String = "Best hikes near Mount Rainier"
  @State private var documentTexts: [String] = [
    "The Skyline Trail offers stunning views of glaciers and wildflowers.",
    "Remember to bring sunscreen and water for your hike.",
    "Consider the Paradise area for easy access to scenic trails.",
    "Baking sourdough bread requires a mature starter.",
    "Tips for optimizing SwiftUI app performance.",
  ]
  @State private var rankedResults: [DocumentResult] = []
  @State private var processingError: String?

  // --- Model Configuration ---
  let modelConfiguration = ModelConfiguration.minilm_l12

  // Computed property for button disabling
  private var isModelReady: Bool {
    loadState == .ready
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        // Header with animation
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("Text Embeddings")
              .font(.largeTitle)
              .fontWeight(.bold)

            Text("Semantic search powered by ML")
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }

          Spacer()

          Image(systemName: "brain.head.profile")
            .font(.system(size: 44))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.blue)
        }
        .padding()

        // Model Status Section
        ModelStatusView(loadState: loadState)

        // Input Section
        InputSectionView(
          queryText: $queryText,
          documentTexts: documentTexts,
          isProcessing: isProcessing,
          isModelReady: isModelReady,
          findAction: { Task { await generateEmbeddingsAndCompare() } }
        )

        // Results Section
        ResultsSectionView(
          rankedResults: rankedResults,
          isProcessing: isProcessing,
          processingError: processingError
        )

        Spacer(minLength: 20)
      }
    }
    .background(Color(.systemGroupedBackground))
    .task { await loadEmbeddingModel() }
    .navigationTitle("Embeddings")
  }

  func loadEmbeddingModel() async {
    guard loadState == .idle else { return }
    await MainActor.run { loadState = .loading }
    do {
      let loadedContainer = try await MLXEmbedders.loadModelContainer(
        configuration: modelConfiguration
      ) { progress in
        Task { @MainActor in
          loadState = .downloading(progress)
        }
      }
      await MainActor.run {
        self.modelContainer = loadedContainer
        self.loadState = .ready
        print("Embedding model loaded successfully.")
      }
    } catch {
      await MainActor.run {
        self.loadState = .error(error)
        print("Failed to load embedding model: \(error)")
      }
    }
  }

  func generateEmbeddingsAndCompare() async {
    guard let container = modelContainer, loadState == .ready else {
      await MainActor.run { processingError = "Model not ready." }
      return
    }
    guard !queryText.isEmpty else {
      await MainActor.run { processingError = "Query cannot be empty." }
      return
    }

    await MainActor.run {
      isProcessing = true
      processingError = nil
      rankedResults = []  // Clear previous results immediately
    }

    let allTexts = [queryText] + documentTexts

    do {
      // Generate embeddings for all texts in one batch
      let rawEmbeddingsMLX: MLXArray = try await container.perform {
        (model: EmbeddingModel, tokenizer: Tokenizer, pooling: Pooling) -> MLXArray in

        let tokenizedInputs = allTexts.map {
          tokenizer.encode(text: $0, addSpecialTokens: true)
        }

        let maxLength = tokenizedInputs.reduce(0) { max($0, $1.count) }

        let paddingTokenId = tokenizer.eosTokenId ?? 0
        let paddingTokenId32 = Int32(paddingTokenId)

        let inputIDsList: [[Int32]] = tokenizedInputs.map { ids -> [Int32] in
          let paddingCount = maxLength - ids.count
          return (ids.map { Int32($0) } + Array(repeating: paddingTokenId32, count: paddingCount))
        }

        // CHANGE: Flatten the list and provide the shape
        let flattenedIDs = inputIDsList.flatMap { $0 }
        let shape = [inputIDsList.count, maxLength]
        let inputIDs = MLXArray(flattenedIDs, shape)

        let attentionMask = (inputIDs .!= paddingTokenId32)
        let tokenTypeIDs = MLXArray.zeros(inputIDs.shape, dtype: .int32)

        // Create position IDs: [0, 1, 2, ..., sequenceLength - 1]
        let sequenceLength = inputIDs.shape[1]
        let positionIDs = MLXArray.arange(sequenceLength)

        // Pass positionIDs to the model call
        let modelOutput = model(
          inputIDs, positionIds: positionIDs, tokenTypeIds: tokenTypeIDs,
          attentionMask: attentionMask)

        // Pass the entire EmbeddingModelOutput to the pooling function
        let finalEmbeddings = pooling(
          modelOutput,  // Pass the whole object
          mask: attentionMask,
          normalize: true,
          applyLayerNorm: true
        )

        finalEmbeddings.eval()
        return finalEmbeddings
      }

      // CHANGE: Convert the resulting MLXArray to [[Float]] here
      guard rawEmbeddingsMLX.dtype == .float32 else {
        throw NSError(
          domain: "EmbeddingError", code: 3,
          userInfo: [
            NSLocalizedDescriptionKey:
              "Unexpected embedding dtype after perform: \(rawEmbeddingsMLX.dtype)"
          ])
      }
      var embeddingsFloats: [[Float]] = []
      for i in 0..<rawEmbeddingsMLX.shape[0] {
        embeddingsFloats.append(rawEmbeddingsMLX[i].asArray(Float.self))
      }

      guard let queryEmbedding = embeddingsFloats.first else {
        throw NSError(
          domain: "EmbeddingError", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "Failed to get query embedding."])
      }
      let documentEmbeddings = Array(embeddingsFloats.dropFirst())

      let queryEmbeddingMLX = MLXArray(queryEmbedding)
      var results: [DocumentResult] = []

      for (index, docEmbeddingFloats) in documentEmbeddings.enumerated() {
        let docEmbeddingMLX = MLXArray(docEmbeddingFloats)
        let similarityMLX = cosineSimilarity(queryEmbeddingMLX, docEmbeddingMLX)
        similarityMLX.eval()
        let score = getScalarFloat(similarityMLX)
        results.append(DocumentResult(text: documentTexts[index], similarity: score))
      }

      await MainActor.run {
        self.rankedResults = results.sorted { $0.similarity > $1.similarity }
        self.isProcessing = false  // Set processing to false *after* results are set
      }

    } catch {
      await MainActor.run {
        processingError = "Processing failed: \(error.localizedDescription)"
        isProcessing = false
        print("Embedding/Comparison failed: \(error)")
      }
    }
  }

  func cosineSimilarity(_ vectorA: MLXArray, _ vectorB: MLXArray, stream: StreamOrDevice = .default)
    -> MLXArray
  {
    let vectorAProcessed = vectorA.squeezed().asType(.float32)
    let vectorBProcessed = vectorB.squeezed().asType(.float32)

    let dotProduct = sum(vectorAProcessed * vectorBProcessed, stream: stream)
    let normA = sqrt(sum(vectorAProcessed * vectorAProcessed, stream: stream))
    let normB = sqrt(sum(vectorBProcessed * vectorBProcessed, stream: stream))

    let magnitude = normA * normB
    let similarity = dotProduct / (magnitude + 1e-8)

    return similarity
  }

  func getScalarFloat(_ array: MLXArray) -> Float {
    // Check dtype before attempting to get item
    guard array.dtype == .float32 else {
      print("Warning: Trying to get Float scalar from non-float32 MLXArray. DType: \(array.dtype)")
      return Float.nan
    }

    // Directly call item(Float.self) for clarity and type safety
    let floatValue = array.item(Float.self)
    return floatValue
  }
}

#Preview {
  NavigationView {
    TextEmbeddingsView()
  }
}
