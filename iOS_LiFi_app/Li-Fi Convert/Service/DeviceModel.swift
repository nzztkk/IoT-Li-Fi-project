//
//  DeviceModel.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 08.04.2026.
//

import Foundation

struct DeviceLog: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let message: String
    let type: LogType
    
    enum LogType {
        case info, error, data
    }
}

struct DeviceStatus {
    var voltage: Float = 0.0
    
    var voltageString: String {
        return String(format: "%.2f V", voltage)
    }
    
    // Расчет процента заряда (для Li-ion аккумулятора 3.3V - 4.2V)
    var batteryLevel: Double {
        let percentage = (voltage - 3.3) / (4.2 - 3.3)
        return Double(min(max(percentage, 0), 1))
    }
}
