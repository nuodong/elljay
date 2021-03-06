//
//  KeychainService.swift
//  elljay
//
//  Created by Akiva Leffert on 8/29/14.
//  Copyright (c) 2014 Akiva Leffert. All rights reserved.
//

import UIKit
import Security

public enum KeychainLoadResult {
    case Success(NSData)
    case Failure(OSStatus)
}

public protocol KeychainServicing {
    func clear() -> OSStatus
    func save(data : NSData) -> OSStatus
    func load() -> KeychainLoadResult
}

class KeychainService : KeychainServicing {
    
    private let serviceName : String
    private let account : String
    
    init(serviceName : String, account : String = "main") {
        self.serviceName = serviceName;
        self.account = account
    }

    func clear() -> OSStatus {
        let keychainQuery =  NSMutableDictionary(dictionary : [
            kSecClass : kSecClassGenericPassword,
            kSecAttrService : serviceName,
            kSecAttrAccount : account,
            ]) as CFDictionaryRef

        let status = SecItemDelete(keychainQuery)
        if(status != errSecSuccess && status != errSecItemNotFound) {
            return status
        }
        return errSecSuccess
    }

    func save(data: NSData) -> OSStatus {
        var status = clear()
        if status != errSecSuccess {
            return status
        }
        
        let keychainQuery =  NSMutableDictionary(dictionary : [
            kSecClass : kSecClassGenericPassword,
            kSecAttrService : serviceName,
            kSecValueData : data,
            kSecAttrAccount : account,
            ]) as CFDictionaryRef
        
        // Add the new keychain item
        status = SecItemAdd(keychainQuery, nil)
        return status
    }

    func load() -> KeychainLoadResult {
        
        var keychainQuery = NSMutableDictionary(dictionary : [
            kSecClass : kSecClassGenericPassword,
            kSecAttrService : serviceName,
            kSecReturnData : kCFBooleanTrue,
            kSecAttrAccount : account,
            kSecMatchLimit : kSecMatchLimitOne
            ]) as CFDictionaryRef
        
        var dataTypeRef : Unmanaged<AnyObject>?
        
        // Search for the keychain items
        let status = SecItemCopyMatching(keychainQuery, &dataTypeRef)
        let opaque = dataTypeRef?.toOpaque()
        
        var contentsOfKeychain: NSString?
        
        if let op = opaque {
            let retrievedData = Unmanaged<NSData>.fromOpaque(op).takeRetainedValue()
            
            return KeychainLoadResult.Success(retrievedData)
        } else {
            return KeychainLoadResult.Failure(status)
        }
    }
    
}
