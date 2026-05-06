//
//  PhoneLighterMessage.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 07.04.2026.
//

import SwiftUI

// Модель лога
struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: String
    let message: String
    let level: LogLevel

    enum LogLevel { case info, success, warning }

    init(message: String, level: LogLevel) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        self.timestamp = formatter.string(from: Date())
        self.message = message
        self.level = level
    }
}

struct PhoneLighterView: View {
    @StateObject private var viewModel = LiFiViewModel()
    @FocusState private var isInputActive: Bool
    @State private var logs: [LogEntry] = [LogEntry(message: "SYSTEM STANDBY", level: .info)]

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(.systemBackground), Color(.secondarySystemBackground)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                headerView.padding(.top, 10)

                terminalView
                    .frame(maxWidth: .infinity)
                    .frame(height: isInputActive ? 160 : 320)
                    .padding(.horizontal)
                    .onChange(of: viewModel.currentStep) { step in
                        updateLogs(for: step)
                    }

                HStack(spacing: 12) {
                    StatusStepView(title: "WAKEUP", isActive: viewModel.currentStep == 1, color: .orange)
                    StatusStepView(title: "PASS V1", isActive: viewModel.currentStep == 2, color: .blue)
                    StatusStepView(title: "PASS V2", isActive: viewModel.currentStep == 3, color: .green)
                }
                .padding(.horizontal, 30)

                Spacer()

                controlsView
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isInputActive)
    }

    private func updateLogs(for step: Int) {
        switch step {
        case 1:
            logs.append(LogEntry(message: "INITIATING UPLINK — SENDING WAKEUP PULSE...", level: .warning))
        case 2:
            logs.append(LogEntry(message: "CALIBRATING BIT_TIME (METRONOME)...", level: .info))
            logs.append(LogEntry(message: "STARTING MANCHESTER PASS V1", level: .info))
        case 3:
            logs.append(LogEntry(message: "RE-SYNCING & PASS V2", level: .info))
        case 0 where !viewModel.isTransmitting:
            if logs.last?.message != "TRANSMISSION COMPLETE" {
                logs.append(LogEntry(message: "TRANSMISSION COMPLETE", level: .success))
            }
        default: break
        }
    }

    func startTransmissionSequence() {
        logs.removeAll()
        Task {
            await viewModel.startTransmissionSequence()
        }
    }

    var terminalView: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(logs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text("[\(entry.timestamp)]")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 10, design: .monospaced))
                                Text("> \(entry.message)")
                                    .foregroundColor(
                                        entry.level == .success ? .green :
                                        entry.level == .warning ? .orange : .primary
                                    )
                            }
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                        }

                        if !viewModel.liveBitStream.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("> MANCHESTER_ENCODED_STREAM:")
                                    Spacer()
                                    Text("L-SYNC ON")
                                        .font(.system(size: 8))
                                        .padding(2)
                                        .background(Color.green.opacity(0.2))
                                }
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundColor(.orange)

                                Text(viewModel.liveBitStream)
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.primary)
                                    .lineSpacing(4)
                                    .id("liveStream")
                            }
                            .padding(.top, 5)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: viewModel.liveBitStream) { _ in
                    withAnimation { proxy.scrollTo("liveStream", anchor: .bottom) }
                }
                .onChange(of: logs.count) { _ in
                    withAnimation { proxy.scrollTo(logs.last?.id, anchor: .bottom) }
                }
            }
        }
        .background(Color.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: 25))
        .overlay(RoundedRectangle(cornerRadius: 25).strokeBorder(.primary.opacity(0.1), lineWidth: 1))
    }

    var headerView: some View {
        HStack(spacing: 15) {
            Label("\(Int(viewModel.ambientLight * 100))%", systemImage: "sun.max.fill")

            if viewModel.isTransmitting {
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                    Text("\(Int(viewModel.effectiveDelay))ms")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.orange)
                .transition(.opacity)
            }

            Spacer()

            Text("SYNC_READY")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
        }
        .padding(.horizontal, 20).padding(.vertical, 10)
        .background(.ultraThinMaterial).clipShape(Capsule())
        .padding(.horizontal)
    }

    var controlsView: some View {
        VStack(spacing: 15) {
            // Кнопки режимов — названия "SLOW"/"MEDIUM"/"FAST" теперь совпадают с ViewModel
            HStack(spacing: 8) {
                ForEach(["SLOW", "MEDIUM", "FAST"], id: \.self) { mode in
                    Button(mode) {
                        viewModel.transmissionMode = mode
                    }
                    .font(.system(size: 10, weight: .bold))
                    .frame(maxWidth: .infinity).frame(height: 40)
                    .background(viewModel.transmissionMode == mode
                                ? Color.primary
                                : Color.primary.opacity(0.05))
                    .foregroundColor(viewModel.transmissionMode == mode
                                     ? Color(.systemBackground)
                                     : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
            }
            .padding(.horizontal)

            HStack(spacing: 12) {
                TextField("", text: $viewModel.message, prompt: Text("ENTER PASSWORD..."))
                    .font(.system(.body, design: .monospaced))
                    .focused($isInputActive)
                    .padding(.horizontal, 15).frame(height: 54)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 18))

                Button(action: startTransmissionSequence) {
                    Image(systemName: "flashlight.on.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Color(.systemBackground))
                        .frame(width: 54, height: 54)
                        .background(viewModel.isTransmitting ? Color.orange : Color.primary)
                        .clipShape(Circle())
                }
                .disabled(viewModel.message.isEmpty || viewModel.isTransmitting)
            }
            .padding(.horizontal)
        }
        .padding(.bottom, isInputActive ? 10 : 30)
    }
}

struct StatusStepView: View {
    let title: String
    let isActive: Bool
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .opacity(0.5)
            RoundedRectangle(cornerRadius: 2)
                .fill(isActive ? color : Color.primary.opacity(0.1))
                .frame(height: 3)
        }
    }
}
