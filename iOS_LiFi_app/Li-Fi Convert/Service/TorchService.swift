//
//  TorchService.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 07.04.2026.

import AVFoundation

class TorchService {
    func setTorch(on: Bool, level: Float) {
        guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else { return }
        
        do {
            try device.lockForConfiguration()
            if on {
                // Уровень яркости должен быть от 0.001 до 1.0
                try device.setTorchModeOn(level: max(0.001, min(level, 1.0)))
            } else {
                device.torchMode = .off
            }
            device.unlockForConfiguration()
        } catch {
            print("Ошибка управления фонариком: \(error)")
        }
    }
    
    func setTorchLevel(_ level: Float) {
        setTorch(on: true, level: level)
    }
}
