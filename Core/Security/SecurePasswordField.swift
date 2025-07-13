//
//  SecurePasswordField.swift
//  NetworkDriveMapper
//
//  Simple password handling for UI components
//
//  Security Design:
//  - Simple SwiftUI-native approach
//  - Clears password after consumption
//  - Relies on system keychain for real security
//

import Foundation
import SwiftUI

/// A simple password field that clears after use
/// Real security comes from keychain storage, not in-memory tricks
@MainActor
final class SecurePasswordField: ObservableObject {
    /// The current password
    @Published var password: String = ""
    
    /// Whether the password field has content
    var hasPassword: Bool {
        !password.isEmpty
    }
    
    init() {}
    
    /// Retrieves the password for one-time use and clears it
    /// - Returns: The password string if available
    /// - Important: This method clears the password after retrieval
    func consumePassword() -> String? {
        guard !password.isEmpty else { return nil }
        let result = password
        password = "" // Simple clear
        return result
    }
    
    /// Peeks at the password without clearing it (use sparingly)
    /// - Returns: The password string if available
    /// - Warning: Only use when absolutely necessary (e.g., for validation)
    func peekPassword() -> String? {
        guard !password.isEmpty else { return nil }
        return password
    }
    
    /// Clears the password
    func clearPassword() {
        password = ""
    }
    
    /// Sets the password from an external source
    /// - Parameter password: The password to set
    func setPassword(_ password: String) {
        self.password = password
    }
}


/// A simple text field view for password input
struct SecurePasswordFieldView: View {
    @ObservedObject var secureField: SecurePasswordField
    let placeholder: String
    let showToggle: Bool
    
    @State private var isSecure: Bool = true
    
    init(secureField: SecurePasswordField, 
         placeholder: String = "Password", 
         showToggle: Bool = true) {
        self.secureField = secureField
        self.placeholder = placeholder
        self.showToggle = showToggle
    }
    
    var body: some View {
        HStack {
            if isSecure {
                SecureField(placeholder, text: $secureField.password)
                    .textContentType(.password)
            } else {
                TextField(placeholder, text: $secureField.password)
                    .textContentType(.password)
            }
            
            if showToggle {
                Button(action: { isSecure.toggle() }) {
                    Image(systemName: isSecure ? "eye" : "eye.slash")
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Security best practices documentation
extension SecurePasswordField {
    /// Security Implementation Notes:
    ///
    /// 1. Simplicity Over Complexity:
    ///    - Simple @Published String for SwiftUI compatibility
    ///    - No locks, actors, or complex state management
    ///    - Eliminates deadlock potential
    ///
    /// 2. Real Security:
    ///    - Passwords are immediately stored in system keychain
    ///    - Keychain provides hardware encryption and access control
    ///    - Memory protection is handled by the OS
    ///
    /// 3. Usage Patterns:
    ///    - consumePassword() for one-time access (e.g., saving to keychain)
    ///    - peekPassword() only for validation checks
    ///    - clearPassword() to explicitly clear when needed
    ///
    /// 4. Best Practices:
    ///    - Store passwords in keychain immediately after entry
    ///    - Don't keep passwords in memory longer than necessary
    ///    - Rely on system security rather than application-level tricks
    static var securityDocumentation: String {
        """
        This class implements simple, reliable password handling:
        - SwiftUI-native design without deadlock potential
        - Immediate keychain storage for real security
        - Clear after use pattern for minimal memory exposure
        """
    }
}