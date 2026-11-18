//
//  KeychainTokenStore.swift
//  PullRequestDashboard
//
//  Created by Automated on 2026-02-06.
//

import Foundation
import Security

public struct KeychainTokenStore {
    private let service: String
    private let account: String

    public init(service: String? = nil, account: String = "github-token") {
        self.account = account
        #if E2E_TESTING
        self.service = service ?? ProcessInfo.processInfo.environment["PRPULSE_E2E_KEYCHAIN_SERVICE"]!
        #else
        self.service = service ?? "com.yourcompany.PullRequestDashboard.token"
        #endif
    }
    
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
        try? readToken()
    }

    public func readToken() throws -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8) else {
            throw KeychainError.utf8EncodingFailed
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
