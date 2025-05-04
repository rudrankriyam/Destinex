//
//  MLXDestinexApp.swift
//  MLXDestinex
//
//  Created by Rudrank Riyam on 5/4/25.
//

import SwiftUI

@main
struct MLXDestinexApp: App {
  var body: some Scene {
    WindowGroup {
      TabView {
        TextEmbeddingsView()
          .tabItem {
            Label("Embeddings", systemImage: "brain.head.profile")
          }
        BasicLLMView()
          .tabItem {
            Label("LLM", systemImage: "text.bubble")
          }
        // Add more tabs here if needed
      }
    }
  }
}
