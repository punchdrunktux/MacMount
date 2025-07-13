//
//  NetworkCredential.swift
//  MacMount
//
//  Model for network authentication credentials
//

import Foundation

struct NetworkCredential: Equatable, Codable {
    let server: String
    let username: String
    let password: String
    let port: Int
    let `protocol`: NetworkProtocol
    
    init(server: String, 
         username: String, 
         password: String, 
         port: Int? = nil, 
         protocol: NetworkProtocol) {
        self.server = server
        self.username = username
        self.password = password
        self.port = port ?? `protocol`.defaultPort
        self.protocol = `protocol`
    }
    
    // Create from ServerConfiguration
    init?(from config: ServerConfiguration, password: String) {
        guard !config.username.isEmpty else { return nil }
        
        self.server = config.serverAddress
        self.username = config.username
        self.password = password
        self.port = config.protocol.defaultPort
        self.protocol = config.protocol
    }
    
    // Keychain identifier
    var keychainIdentifier: String {
        "\(`protocol`.rawValue.lowercased())://\(username)@\(server):\(port)"
    }
}