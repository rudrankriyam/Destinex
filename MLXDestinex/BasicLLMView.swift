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

struct MessageBubble: View {
    let text: String
    let isUser: Bool
    
    var body: some View {
        Text(text)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isUser ? Color.indigo : Color(.systemGray6))
            .foregroundColor(isUser ? .white : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
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
    @State private var prompt: String = "What is the meaning of destiny?"
    @State private var generatedText: String = ""
    @State private var isGenerating: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            ZStack {
                Color(.systemGray6)
                    .ignoresSafeArea()
                
                Text("MLX Destinex")
                    .font(.headline)
                    .padding()
            }
            .frame(height: 44)
            
            // Chat area
            ScrollView {
                VStack(spacing: 16) {
                    // Status messages
                    Group {
                        switch loadState {
                        case .idle:
                            Text("Model not loaded yet")
                                .foregroundColor(.secondary)
                        case .loading:
                            HStack {
                                ProgressView()
                                Text("Loading Model...")
                                    .foregroundColor(.secondary)
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
                            Text("Model Ready")
                                .foregroundColor(.green)
                        case .error(let error):
                            Text("Error: \(error.localizedDescription)")
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    
                    // Messages
                    if !prompt.isEmpty {
                        MessageBubble(text: prompt, isUser: true)
                    }
                    
                    if !generatedText.isEmpty {
                        MessageBubble(text: generatedText, isUser: false)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            
            // Input area
            VStack(spacing: 0) {
                Divider()
                HStack(spacing: 12) {
                    TextField("Type your message...", text: $prompt)
                        .padding(12)
                        .background(Color(.systemGray6))
                        .cornerRadius(20)
                    
                    Button(action: { 
                        Task { await generate() }
                    }) {
                        Image(systemName: isGenerating ? "stop.circle.fill" : "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundColor(prompt.isEmpty ? .gray : .indigo)
                    }
                    .disabled(loadState != .ready || isGenerating || prompt.isEmpty)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemBackground))
            }
        }
        .task { await loadModel() }
    }
    
    // Function to load the model asynchronously
    func loadModel() async {
        guard loadState == .idle else { return } // Prevent multiple loads
        loadState = .loading
        do {
            // Use the shared factory to load the container
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
            prompt = "" // Clear the input after sending
        }
    }
}

#Preview {
    BasicLLMView()
}
