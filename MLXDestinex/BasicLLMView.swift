import SwiftUI
import MLX
import MLXLLM
import MLXLMCommon

// Define a basic LoadState enum (adapt as needed based on MLXLLM details)
enum LoadState: Equatable {
    case idle
    case loading
    case downloading(Progress)
    case ready
    case error(Error)
    
    // Conformance for Equatable, ignoring associated values for simplicity here
    static func == (lhs: LoadState, rhs: LoadState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.downloading, .downloading), (.ready, .ready), (.error, .error):
            return true // Basic comparison; doesn't compare associated values like Progress or Error
        default:
            return false
        }
    }
}


struct BasicLLMView: View {
    // Model Configuration
    // NOTE: Using a smaller model initially might be faster for testing.
    // You can change this later, e.g., LLMRegistry.mistral_7b_instruct_q4_0
    let modelConfiguration = LLMRegistry.qwen3_1_7b_4bit
    
    // State Variables
    @State private var modelContainer: ModelContainer? = nil
    @State private var loadState: LoadState = .idle
    @State private var prompt: String = "Write a short poem about Swift programming:"
    @State private var generatedText: String = ""
    @State private var isGenerating: Bool = false
    
    var body: some View {
        VStack {
            Text("MLX Swift LLM Demo")
                .font(.title)
            
            TextEditor(text: $prompt)
                .frame(height: 100)
                .border(Color.gray)
                .padding(.horizontal)
            
            Button(isGenerating ? "Generating..." : "Generate Text") {
                Task { await generate() }
            }
            .disabled(loadState != .ready || isGenerating)
            .padding(.bottom)
            
            // Display Loading/Downloading State
            switch loadState {
            case .idle:
                Text("Model not loaded yet.")
            case .loading:
                ProgressView("Loading Model...")
            case .downloading(let progress):
                ProgressView("Downloading: \(Int(progress.fractionCompleted * 100))%", value: progress.fractionCompleted)
                    .padding(.horizontal)
            case .ready:
                Text("Model Ready.")
                    .foregroundColor(.green)
            case .error(let error):
                Text("Error loading model: \(error.localizedDescription)")
                    .foregroundColor(.red)
            }
            
            ScrollView {
                Text(generatedText)
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled) // Allow text selection
            }
            
            Spacer()
        }
        .padding()
        // Use task modifier for async work tied to view lifecycle
        .task {
            await loadModel()
        }
    }
    
    // Function to load the model asynchronously
    func loadModel() async {
        guard loadState == .idle else { return } // Prevent multiple loads
        loadState = .loading
        do {
            // Use the shared factory to load the container
            // CHANGE: Use Task { @MainActor in ... } instead of await MainActor.run to keep the closure synchronous
            let loadedContainer = try await LLMModelFactory.shared.loadContainer(configuration: modelConfiguration) { progress in
                // Update state on main actor asynchronously without awaiting
                Task { @MainActor in
                    loadState = .downloading(progress)
                }
            }
            // Update state on main actor
            await MainActor.run {
                modelContainer = loadedContainer
                loadState = .ready
            }
        } catch {
            // Update state on main actor
            await MainActor.run {
                loadState = .error(error)
                print("Failed to load model: \(error)")
            }
        }
    }
    
    // Function to generate text based on the prompt
    func generate() async {
        guard let container = modelContainer else {
            await MainActor.run { generatedText = "Model not loaded." }
            return
        }
        guard !isGenerating else { return } // Prevent concurrent generations
        
        await MainActor.run {
            isGenerating = true
            generatedText = "Generating..." // Initial message
        }
        
        do {
            // Use perform to get the ModelContext for generation
            let stream = try await container.perform { (context: ModelContext) in
                // Prepare input
                let chat = await [Chat.Message.user(prompt)]
                let userInput = UserInput(chat: chat)
                let lmInput = try await context.processor.prepare(input: userInput)
                
                // Set generation parameters
                let parameters = GenerateParameters(temperature: 0.7)
                
                // Generate text stream
                return try MLXLMCommon.generate(input: lmInput, parameters: parameters, context: context)
            }
            
            // Process the stream of generated tokens
            var preparingFirstToken = true
            for try await generation in stream {
                await MainActor.run {
                    // Clear "Generating..." on first token
                    if preparingFirstToken {
                        generatedText = ""
                        preparingFirstToken = false
                    }
                    generatedText += generation.chunk ?? ""
                }
            }
        } catch {
            await MainActor.run {
                generatedText = "Error during generation: \(error.localizedDescription)"
                print("Generation failed: \(error)")
            }
        }
        
        await MainActor.run {
            isGenerating = false // Reset generation state
        }
    }
}

#Preview {
    BasicLLMView()
}
