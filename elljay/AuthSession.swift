//
//  Session.swift
//  elljay
//
//  Created by Akiva Leffert on 8/14/14.
//  Copyright (c) 2014 Akiva Leffert. All rights reserved.
//

import UIKit
import Security

class AuthSessionInfo : NSCoding {
    let username : String
    let password : String
    let challenge : String
    let challengeExpiration : NSDate
    
    init(username : String, password : String, challenge : String, challengeExpiration : NSDate) {
        self.username = username
        self.password = password
        self.challenge = challenge
        self.challengeExpiration = challengeExpiration
    }
    
    required init(coder : NSCoder) {
        self.username = coder.decodeObjectForKey("username") as String
        self.password = coder.decodeObjectForKey("password") as String
        self.challenge = coder.decodeObjectForKey("challenge") as String
        self.challengeExpiration = coder.decodeObjectForKey("challengeExpiration") as NSDate
    }
    
    func encodeWithCoder(coder: NSCoder) {
        coder.encodeObject(self.username, forKey:"username")
        coder.encodeObject(self.password, forKey:"password")
        coder.encodeObject(self.challenge, forKey:"challenge")
        coder.encodeObject(self.challengeExpiration, forKey:"challengeExpiration")
    }
    
    var expired : Bool {
        return challengeExpiration > NSDate.date()
    }
    
    var challengeResponse : String! {
        return ELJCrypto.md5OfString(self.challenge + ELJCrypto.md5OfString(self.password))
    }
}

class AuthSession {
    private let keychain : KeychainService
    
    private(set) var storage : AuthSessionInfo?
    
    init(keychain : KeychainService) {
        self.keychain = keychain
    }
    
    func loadFromKeychainIfPossible() {
        switch(keychain.load()) {
        case let .Success(storageData):
            storage = NSKeyedUnarchiver.unarchiveObjectWithData(storageData) as? AuthSessionInfo
        case let .Failure(err):
            assert(Int(err) == errSecItemNotFound, "Unexpected keychain error: \(err)")
            break
        }
    }

    func saveToKeychain() {
        let data : NSData? = storage.bind {s in return NSKeyedArchiver.archivedDataWithRootObject(s) }
        let err : OSStatus? = data.bind {d in return self.keychain.save(d) }
        assert(err == nil, "Unexpected keychain error: \(err)")
    }
    
    func store(storage : AuthSessionInfo) {
        self.storage = storage
    }
    
    func update(#challenge : String, challengeExpiration : NSDate) {
        self.storage = self.storage.bind {(s : AuthSessionInfo) in
            return AuthSessionInfo(username: s.username, password: s.password, challenge: challenge, challengeExpiration: challengeExpiration)
        }
    }
    
    var hasCredentials : Bool {
        let result : Bool? = storage.bind {s in
            return s.expired
        }
        return result ?? false
    }
    
    var hasExpiredChallenge : Bool {
        return !hasCredentials && storage != nil
    }
}


protocol AuthSessionOwner {
    var authSession : AuthSession { get }
}