//
//  ContentView.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 31.03.2026.
//

import SwiftUI

struct ContentView: View {
    // Состояние для отслеживания выбранной вкладки (опционально)
    @State private var selectedTab = 0
    
    var body: some View {
        TabView(selection: $selectedTab) {
            
            // Первая страница: Основной экран Li-Fi
            NavigationStack {
                VStack(spacing: 20) {
                    PhoneLighterView()
                }
                
            }
            .tabItem {
                Label("Lighter", systemImage: "lightbulb.min.fill")
            }
            .tag(0)
            
        
            
            // Третья страница: Настройки (как пример для полноценного бара)
            NavigationStack {
                VStack(spacing: 20){
                    SettingsView()
                }
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape.fill")
            }
            .tag(2)
        }
        // Устанавливаем акцентный цвет для активных иконок
        .tint(.blue)
    }
}

#Preview {
    ContentView()
}
