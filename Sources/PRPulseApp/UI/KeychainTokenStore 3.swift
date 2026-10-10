//
//  KeychainTokenStore.swift
//  PullRequestDashboard
//
//  Created by Automated on 2026-02-06.
//

import Foundation
import Security

public struct KeychainTokenStore {
    private var service: String {
        #if E2E_TESTING
        return ProcessInfo.processInfo.environment["PRPULSE_E2E_KEYCHAIN_SERVICE"]!
        #else
        return "com.yourcompany.PullRequestDashboard.token"
        #endif
    }
    private let account = "github-token"
    
    private func baseQuery() -> [String: Any] {
        return [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
    
    public func setToken(_ token: String) throws {
        guard let tokenData = token.data(using: .utf8) else {
            throw KeychainError.utf8EncodingFailed
        }
        var query = baseQuery()
        
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            // Update existing item
            let attributesToUpdate = [kSecValueData as String: tokenData]
            let updateStatus = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
            if updateStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(updateStatus)
            }
        case errSecItemNotFound:
            // Add new item
            query[kSecValueData as String] = tokenData
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            if addStatus != errSecSuccess {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }
    
    public func getToken() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            return nil
        }
        return token
    }
    
    public func clearToken() throws {
        let query = baseQuery()
        let status = SecItemDelete(query as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

public enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
    case utf8EncodingFailed
}
