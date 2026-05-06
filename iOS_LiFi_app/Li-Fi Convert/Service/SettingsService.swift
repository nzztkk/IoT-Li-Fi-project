//
//  SettingsService.swift
//  Li-Fi Convert
//
//  Created by Nurkhat on 07.04.2026.
//

import Foundation
import Combine

class SettingsService: ObservableObject {
    // Скорости в миллисекундах (BIT_TIME)
    @Published var ecoDelay: Double { didSet { save() } }
    @Published var standardDelay: Double { didSet { save() } }
    @Published var turboDelay: Double { didSet { save() } }
    
    // Паузы в секундах
    @Published var wakeupPause: Double { didSet { save() } }
    @Published var retryInterval: Double { didSet { save() } }

    init() {
        // Загрузка или дефолтные значения
        self.ecoDelay = UserDefaults.standard.double(forKey: "ecoDelay") == 0 ? 200 : UserDefaults.standard.double(forKey: "ecoDelay")
        self.standardDelay = UserDefaults.standard.double(forKey: "standardDelay") == 0 ? 100 : UserDefaults.standard.double(forKey: "standardDelay")
        self.turboDelay = UserDefaults.standard.double(forKey: "turboDelay") == 0 ? 50 : UserDefaults.standard.double(forKey: "turboDelay")
        
        self.wakeupPause = UserDefaults.standard.double(forKey: "wakeupPause") == 0 ? 0.3 : UserDefaults.standard.double(forKey: "wakeupPause")
        self.retryInterval = UserDefaults.standard.double(forKey: "retryInterval") == 0 ? 2.0 : UserDefaults.standard.double(forKey: "retryInterval")
    }

    private func save() {
        UserDefaults.standard.set(ecoDelay, forKey: "ecoDelay")
        UserDefaults.standard.set(standardDelay, forKey: "standardDelay")
        UserDefaults.standard.set(turboDelay, forKey: "turboDelay")
        UserDefaults.standard.set(wakeupPause, forKey: "wakeupPause")
        UserDefaults.standard.set(retryInterval, forKey: "retryInterval")
    }
    
    
    // Метод для записи набора значений в UserDefaults
    func applyAll(eco: Double, std: Double, turbo: Double, wakeup: Double, retry: Double) {
        self.ecoDelay = eco
        self.standardDelay = std
        self.turboDelay = turbo
        self.wakeupPause = wakeup
        self.retryInterval = retry
        
        UserDefaults.standard.set(ecoDelay, forKey: "ecoDelay")
        UserDefaults.standard.set(standardDelay, forKey: "standardDelay")
        UserDefaults.standard.set(turboDelay, forKey: "turboDelay")
        UserDefaults.standard.set(wakeupPause, forKey: "wakeupPause")
        UserDefaults.standard.set(retryInterval, forKey: "retryInterval")
    }

    // Логика ограничений
    func validateEco() {
        if ecoDelay <= standardDelay { ecoDelay = standardDelay + 5 }
    }

    func validateStandard() {
        if standardDelay >= ecoDelay { standardDelay = ecoDelay - 5 }
        if standardDelay <= turboDelay { standardDelay = turboDelay + 5 }
    }

    func validateTurbo() {
        if turboDelay >= standardDelay { turboDelay = standardDelay - 5 }
    }
}
