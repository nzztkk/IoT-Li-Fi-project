import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = SettingsService()
    
    @State private var tempEco: Double = 0
    @State private var tempStd: Double = 0
    @State private var tempTurbo: Double = 0
    @State private var tempWakeup: Double = 0
    @State private var tempRetry: Double = 0
    
    @State private var hasChanges: Bool = false

    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Тайминги битов (ms)").font(.system(.caption, design: .monospaced))) {
                    
                    // SLOW (Должен быть самым большим числом)
                    timingSlider(title: "SLOW", value: $tempEco, range: 100...500, color: .green) {
                        validateChainFromSlow()
                    }
                    
                    // MEDIUM (Середина)
                    timingSlider(title: "MEDIUM", value: $tempStd, range: 40...400, color: .blue) {
                        validateChainFromMedium()
                    }
                    
                    // FAST (Самое маленькое число)
                    timingSlider(title: "FAST", value: $tempTurbo, range: 10...200, color: .orange) {
                        validateChainFromFast()
                    }
                }
                
                Section(header: Text("Паузы (секунды)").font(.system(.caption, design: .monospaced))) {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Wakeup Pause")
                            Spacer()
                            Text(String(format: "%.1f s", tempWakeup)).bold()
                        }
                        Slider(value: $tempWakeup, in: 0.1...1.5, step: 0.1)
                            .onChange(of: tempWakeup) { _ in hasChanges = true }
                    }
                    
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Retry Interval")
                            Spacer()
                            Text(String(format: "%.1f s", tempRetry)).bold()
                        }
                        Slider(value: $tempRetry, in: 0.5...5.0, step: 0.1)
                            .onChange(of: tempRetry) { _ in hasChanges = true }
                    }
                }
            }
            .navigationTitle("Настройки")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: saveAction) {
                        Text("Сохранить")
                            .bold()
                            .foregroundColor(hasChanges ? .blue : .secondary)
                    }
                    .disabled(!hasChanges)
                }
            }
            .onAppear(perform: loadCurrentSettings)
        }
    }
    
    // MARK: - Логика валидации (Каскадная)
    
    // Если меняем SLOW, он может "толкать" MEDIUM вниз, а тот в свою очередь FAST
    private func validateChainFromSlow() {
        if tempEco <= tempStd {
            tempStd = tempEco - 1
        }
        if tempStd <= tempTurbo {
            tempTurbo = tempStd - 1
        }
        hasChanges = true
    }
    
    // Если меняем MEDIUM, он толкает SLOW вверх или FAST вниз
    private func validateChainFromMedium() {
        if tempStd >= tempEco {
            tempEco = tempStd + 1
        }
        if tempStd <= tempTurbo {
            tempTurbo = tempStd - 1
        }
        hasChanges = true
    }
    
    // Если меняем FAST, он толкает MEDIUM вверх, а тот SLOW
    private func validateChainFromFast() {
        if tempTurbo >= tempStd {
            tempStd = tempTurbo + 1
        }
        if tempStd >= tempEco {
            tempEco = tempStd + 1
        }
        hasChanges = true
    }

    private func loadCurrentSettings() {
        tempEco = settings.ecoDelay
        tempStd = settings.standardDelay
        tempTurbo = settings.turboDelay
        tempWakeup = settings.wakeupPause
        tempRetry = settings.retryInterval
        hasChanges = false
    }
    
    private func saveAction() {
        settings.applyAll(eco: tempEco, std: tempStd, turbo: tempTurbo, wakeup: tempWakeup, retry: tempRetry)
        hasChanges = false
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    @ViewBuilder
    func timingSlider(title: String, value: Binding<Double>, range: ClosedRange<Double>, color: Color, onEdit: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(.subheadline, design: .monospaced))
                Spacer()
                Text("\(Int(value.wrappedValue)) ms").bold().foregroundColor(color)
            }
            // Используем onChange для мгновенной реакции во время перетаскивания
            Slider(value: value, in: range, step: 1)
                .onChange(of: value.wrappedValue) { _ in
                    onEdit()
                }
                .accentColor(color)
        }
    }
}
