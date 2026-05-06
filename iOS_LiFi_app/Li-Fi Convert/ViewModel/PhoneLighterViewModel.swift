//
//  LiFiViewModel.swift
//  Li-Fi Convert
//
//  Точный тайминг через CADisplayLink.
//  Дефолтные значения подобраны под скорость фоторезистора:
//    SLOW   = 600ms  (надёжно при любом освещении)
//    MEDIUM = 400ms  (рекомендуется)
//    FAST   = 300ms  (только при хорошем контрасте)
//

import Foundation
import AVFoundation
import SwiftUI
import Combine
import QuartzCore

@MainActor
final class LiFiViewModel: ObservableObject {
    @Published var message: String = "OPEN!"
    @Published var torchLevel: Float = 1.0
    @Published var isTransmitting = false
    @Published var transmissionMode: String = "MEDIUM"  // "SLOW" | "MEDIUM" | "FAST"

    @Published var currentStep: Int = 0
    @Published var ambientLight: Double = 0.0
    @Published var liveBitStream: String = ""
    @Published var effectiveDelay: Double = 0.0

    private let torchService = TorchService()
    private let settings = SettingsService()
    private var ambientTimer: AnyCancellable?

    // Значения BIT_TIME в секундах, подобранные под фоторезистор
    // Менять здесь, а не в SettingsService
    private let bitTimeSlow:   CFTimeInterval = 0.600  // 600ms
    private let bitTimeMedium: CFTimeInterval = 0.400  // 400ms
    private let bitTimeFast:   CFTimeInterval = 0.300  // 300ms

    // CADisplayLink
    private var displayLink: CADisplayLink?
    private var schedule: [FlashEvent] = []
    private var scheduleStart: CFTimeInterval = 0
    private var scheduleIndex: Int = 0
    private var onComplete: (() -> Void)?

    private struct FlashEvent {
        let time: CFTimeInterval   // секунды от начала расписания
        let on: Bool
        let streamChar: String?    // символ для liveBitStream (nil = не писать)
    }

    init() {
        ambientTimer = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.ambientLight = Double(UIScreen.main.brightness)
            }
    }

    // ─────────────────────────────────────────
    // MARK: - Запуск
    // ─────────────────────────────────────────

    func startTransmissionSequence() async {
        guard !message.isEmpty, !isTransmitting else { return }
        isTransmitting = true
        liveBitStream = ""
        effectiveDelay = 0

        let bitTime = selectedBitTime()
        liveBitStream = "BIT_TIME: \(Int(bitTime * 1000))ms\n"
        liveBitStream += "WAKEUP > "

        schedule = buildSchedule(text: message, bitTime: bitTime)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            self.onComplete = { continuation.resume() }
            self.startDisplayLink()
        }

        torchService.setTorch(on: false, level: torchLevel)
        isTransmitting = false
        currentStep = 0
    }

    // ─────────────────────────────────────────
    // MARK: - Построение расписания
    // ─────────────────────────────────────────

    private func buildSchedule(text: String, bitTime: CFTimeInterval) -> [FlashEvent] {
        var events: [FlashEvent] = []
        var t: CFTimeInterval = 0
        let half = bitTime / 2.0

        // ── WAKEUP: 1.5 секунды непрерывного света ──
        events.append(FlashEvent(time: t, on: true,  streamChar: nil))
        t += 1.5
        events.append(FlashEvent(time: t, on: false, streamChar: nil))

        // Пауза после wakeup — не менее 2 BIT_TIME
        t += max(0.5, bitTime * 2)

        // ── PASS V1 ──
        t = appendPass(to: &events, text: text, half: half, t: t, label: "\nV1 > ")

        // Пауза между проходами — не менее 3 BIT_TIME
        t += max(1.0, bitTime * 3)

        // ── PASS V2 ──
        t = appendPass(to: &events, text: text, half: half, t: t, label: "\nV2 > ")

        // Финальное выключение
        events.append(FlashEvent(time: t + half, on: false, streamChar: "\nDONE"))
        return events
    }

    @discardableResult
    private func appendPass(
        to events: inout [FlashEvent],
        text: String,
        half: CFTimeInterval,
        t: CFTimeInterval,
        label: String
    ) -> CFTimeInterval {
        var t = t

        // Метроном: [светло][темно][светло][темно]
        // Arduino видит два восходящих фронта и измеряет BIT_TIME между ними
        for _ in 0..<2 {
            events.append(FlashEvent(time: t, on: true,  streamChar: nil)); t += half
            events.append(FlashEvent(time: t, on: false, streamChar: nil)); t += half
        }

        // Пауза перед данными = halfBit/2
        t += half / 2.0

        // Данные
        let bytes = Array(text.utf8)
        var isFirst = true
        for byte in bytes {
            for bit in 0..<8 {
                let bitValue = (byte >> (7 - bit)) & 1
                let prefix: String? = isFirst ? label : nil
                isFirst = false

                if bitValue == 1 {
                    // 1: тёмно(half) → светло(half)
                    events.append(FlashEvent(time: t, on: false, streamChar: prefix)); t += half
                    events.append(FlashEvent(time: t, on: true,  streamChar: "1"));    t += half
                } else {
                    // 0: светло(half) → тёмно(half)
                    events.append(FlashEvent(time: t, on: true,  streamChar: prefix)); t += half
                    events.append(FlashEvent(time: t, on: false, streamChar: "0"));    t += half
                }
            }
            events.append(FlashEvent(time: t, on: false, streamChar: " "))
        }

        return t
    }

    // ─────────────────────────────────────────
    // MARK: - CADisplayLink
    // ─────────────────────────────────────────

    private func startDisplayLink() {
        scheduleIndex = 0
        scheduleStart = CACurrentMediaTime()

        let link = CADisplayLink(target: self, selector: #selector(tick))
        link.add(to: .main, forMode: .common)
        displayLink = link
        currentStep = 1
    }

    @objc private func tick() {
        guard let link = displayLink else { return }
        let elapsed = link.timestamp - scheduleStart

        while scheduleIndex < schedule.count {
            let event = schedule[scheduleIndex]
            guard elapsed >= event.time else { break }

            torchService.setTorch(on: event.on, level: torchLevel)

            if let char = event.streamChar {
                liveBitStream += char
            }

            // Диагностика джиттера
            let drift = (elapsed - event.time) * 1000
            effectiveDelay = (effectiveDelay * 0.85) + (drift * 0.15)

            scheduleIndex += 1
        }

        // Обновляем шаг UI
        let total = schedule.last?.time ?? 1
        let mid   = total / 2.0
        if elapsed < 1.5 {
            if currentStep != 1 { currentStep = 1 }
        } else if elapsed < mid {
            if currentStep != 2 { currentStep = 2 }
        } else {
            if currentStep != 3 { currentStep = 3 }
        }

        // Завершение
        if scheduleIndex >= schedule.count {
            link.invalidate()
            displayLink = nil
            onComplete?()
            onComplete = nil
        }
    }

    // ─────────────────────────────────────────
    // MARK: - Helpers
    // ─────────────────────────────────────────

    private func selectedBitTime() -> CFTimeInterval {
        switch transmissionMode {
        case "FAST": return bitTimeFast
        case "SLOW": return bitTimeSlow
        default:     return bitTimeMedium
        }
    }
}
