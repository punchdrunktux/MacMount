//
//  PersistenceManager.swift
//  MacMount
//
//  Handles data persistence using UserDefaults
//

import Foundation
import OSLog

// MARK: - Repository Protocol

protocol ServerConfigurationRepository {
    func fetchAll() throws -> [ServerConfiguration]
    func saveAll(_ configurations: [ServerConfiguration]) throws
    func save(_ configuration: ServerConfiguration) throws
    func delete(_ id: UUID) throws
    
    // Async variants to avoid blocking in async contexts
    func fetchAllAsync() async throws -> [ServerConfiguration]
    func saveAllAsync(_ configurations: [ServerConfiguration]) async throws
    func saveAsync(_ configuration: ServerConfiguration) async throws
    func deleteAsync(_ id: UUID) async throws
}

// MARK: - UserDefaults Implementation

class UserDefaultsServerRepository: ServerConfigurationRepository {
    private let defaults = UserDefaults.standard
    private let key = "ServerConfigurations"
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "Persistence")
    
    init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }
    
    func fetchAll() throws -> [ServerConfiguration] {
        guard let data = defaults.data(forKey: key) else {
            logger.info("No server configurations found")
            return []
        }
        
        do {
            let configs = try decoder.decode([ServerConfiguration].self, from: data)
            logger.info("Loaded \(configs.count) server configurations")
            return configs
        } catch {
            logger.error("Failed to decode server configurations: \(error)")
            throw PersistenceError.decodingFailed(error)
        }
    }
    
    func saveAll(_ configurations: [ServerConfiguration]) throws {
        do {
            let data = try encoder.encode(configurations)
            defaults.set(data, forKey: key)
            logger.info("Saved \(configurations.count) server configurations")
        } catch {
            logger.error("Failed to encode server configurations: \(error)")
            throw PersistenceError.encodingFailed(error)
        }
    }
    
    func save(_ configuration: ServerConfiguration) throws {
        var configs = try fetchAll()
        
        if let index = configs.firstIndex(where: { $0.id == configuration.id }) {
            configs[index] = configuration
        } else {
            configs.append(configuration)
        }
        
        try saveAll(configs)
    }
    
    func delete(_ id: UUID) throws {
        var configs = try fetchAll()
        configs.removeAll { $0.id == id }
        try saveAll(configs)
    }
    
    // MARK: - Async Variants
    
    func fetchAllAsync() async throws -> [ServerConfiguration] {
        // Simple direct call - UserDefaults is thread-safe
        return try fetchAll()
    }
    
    func saveAllAsync(_ configurations: [ServerConfiguration]) async throws {
        // Simple direct call - UserDefaults is thread-safe
        try saveAll(configurations)
    }
    
    func saveAsync(_ configuration: ServerConfiguration) async throws {
        // Simple direct call - UserDefaults is thread-safe
        try save(configuration)
    }
    
    func deleteAsync(_ id: UUID) async throws {
        // Simple direct call - UserDefaults is thread-safe
        try delete(id)
    }
}

// MARK: - General Persistence Manager

class PersistenceManager {
    static let shared = PersistenceManager()
    
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "MacMount", category: "Persistence")
    
    private init() {
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        decoder.dateDecodingStrategy = .iso8601
        encoder.dateEncodingStrategy = .iso8601
    }
    
    // MARK: - Generic Save/Load
    
    func save<T: Codable>(_ object: T, to key: String) throws {
        do {
            let data = try encoder.encode(object)
            UserDefaults.standard.set(data, forKey: key)
            logger.debug("Saved object to key: \(key)")
        } catch {
            logger.error("Failed to save object to key \(key): \(error)")
            throw PersistenceError.encodingFailed(error)
        }
    }
    
    func load<T: Codable>(_ type: T.Type, from key: String) throws -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            logger.debug("No data found for key: \(key)")
            return nil
        }
        
        do {
            let object = try decoder.decode(type, from: data)
            logger.debug("Loaded object from key: \(key)")
            return object
        } catch {
            logger.error("Failed to load object from key \(key): \(error)")
            throw PersistenceError.decodingFailed(error)
        }
    }
    
    // MARK: - App Settings
    
    func saveSetting<T>(_ value: T, for key: AppSettingKey) {
        UserDefaults.standard.set(value, forKey: key.rawValue)
    }
    
    func loadSetting<T>(for key: AppSettingKey, defaultValue: T) -> T {
        UserDefaults.standard.object(forKey: key.rawValue) as? T ?? defaultValue
    }
    
    // MARK: - Data Migration
    
    func migrate() {
        let currentVersion = UserDefaults.standard.integer(forKey: "DataVersion")
        let targetVersion = 1
        
        guard currentVersion < targetVersion else { return }
        
        logger.info("Migrating data from version \(currentVersion) to \(targetVersion)")
        
        switch currentVersion {
        case 0:
            // Initial version, no migration needed
            break
        default:
            break
        }
        
        UserDefaults.standard.set(targetVersion, forKey: "DataVersion")
        logger.info("Data migration completed")
    }
}

// MARK: - Supporting Types

enum PersistenceError: LocalizedError {
    case encodingFailed(Error)
    case decodingFailed(Error)
    case migrationFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .encodingFailed(let error):
            return "Failed to save data: \(error.localizedDescription)"
        case .decodingFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .migrationFailed(let reason):
            return "Data migration failed: \(reason)"
        }
    }
}

enum AppSettingKey: String {
    case launchAtLogin
    case showNotifications
    case autoMountOnWake
    case autoMountOnNetworkChange
    case hideMenuBarIconWhenDisconnected
    case enableDebugLogging
}