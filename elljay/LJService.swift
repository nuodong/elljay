//
//  Service.swift
//  elljay
//
//  Created by Akiva Leffert on 8/14/14.
//  Copyright (c) 2014 Akiva Leffert. All rights reserved.
//

import Foundation
import UIKit

struct Request<A, B> {
    let urlRequest : B -> NSURLRequest
    let parser : NSData -> Result<A>
}

typealias ChallengeInfo = (sessionInfo : AuthSessionInfo, challenge : String)


// The LJ API has a year 2038 bug. Sigh
private extension Int32 {
    func dateFromUnixSeconds() -> NSDate {
        return NSDate(timeIntervalSince1970: NSTimeInterval(self))
    }
}

struct DateUtils {
    
    static private func standardTimeZone() -> NSTimeZone {
        // TODO figure this out. I'm hoping it's GMT
        return NSTimeZone(forSecondsFromGMT: 0)
    }
    
    static private var standardFormat : NSString {
        return "yyyy-MM-dd HH:mm:ss"
    }
    
    static private var standardFormatter : NSDateFormatter {
        let formatter = NSDateFormatter()
            formatter.timeZone = standardTimeZone()
            formatter.dateFormat = standardFormat
            return formatter
    }
    
    static func stringFromDate(date : NSDate) -> String {
        return standardFormatter.stringFromDate(date)
    }
    
    static func dateFromString(string : String) -> NSDate? {
        return standardFormatter.dateFromString(string)
    }
}

struct GetChallengeResponse {
    let challenge : String
    let expireTime : NSDate
    let serverTime : NSDate
}

protocol ChallengeRequestable {
    func getChallenge() -> (NSURLRequest, NSData -> Result<GetChallengeResponse>)
}

private let LJServiceVersion : Int32 = 1


// TODO change to a class variable once they're supported
let LJServiceErrorDomain = "com.akivaleffert.elljay.LJService"
let LJServiceErrorMalformedResponseCode = -100

class LJService : ChallengeRequestable {
    let url = NSURL(scheme: "https", host: "livejournal.com", path: "/interface/xmlrpc")!
    let name = "LiveJournal!"

    init() {
    }
    
    private func malformedResponseError(description : String) -> NSError {
        return NSError(domain : LJServiceErrorDomain, code : LJServiceErrorMalformedResponseCode, userInfo : [NSLocalizedDescriptionKey : description])
    }
    
    private func XMLRPCURLRequest(#name : String, params : [String : XMLRPCParam]) -> NSURLRequest {
        let request = NSMutableURLRequest(URL: self.url)
        let paramStruct = XMLRPCParam.XStruct(params)
        request.setupXMLRPCCall(path: "LJ.XMLRPC." + name, parameters: [paramStruct])
        return request
    }
    
    func wrapXMLRPCParser<A>(parser : XMLRPCParam -> A?) -> (NSData -> Result<A>) {
        let dataParser : NSData -> Result<A> = {data in
            let result = XMLRPCParser().from(data:NSMutableData(data:data))
            return result.bind {params -> Result<A> in
                if countElements(params) > 0 {
                    let parsed = parser(params[0])
                    if let p = parsed {
                        return Success(p)
                    }
                    else {
                        return Failure(self.malformedResponseError("Bad Response"))
                    }
                }
                else {
                    return Failure(self.malformedResponseError("Empty Body"))
                }
            }
        }
        return dataParser
    }

    private func authenticatedXMLRPCRequest<A>(#name : String, params : [String : XMLRPCParam], parser : XMLRPCParam -> A?) -> Request<A, ChallengeInfo> {
        let generator : (sessionInfo : AuthSessionInfo, challenge : String) -> NSURLRequest = {(sessionInfo, challenge) in
            var finalParams = params
            finalParams["ver"] = XMLRPCParam.XInt(LJServiceVersion)
            finalParams["username"] = XMLRPCParam.XString(sessionInfo.username)
            finalParams["auth_challenge"] = XMLRPCParam.XString(challenge)
            finalParams["auth_response"] = XMLRPCParam.XString(sessionInfo.challengeResponse(challenge))
            finalParams["auth_method"] = XMLRPCParam.XString("challenge")
            
            return self.XMLRPCURLRequest(name: name, params: finalParams)
        }
        return Request(urlRequest: generator, parser: wrapXMLRPCParser(parser))
    }
    
    func getChallenge() -> (NSURLRequest, NSData -> Result<GetChallengeResponse>) {
        let parser : XMLRPCParam -> GetChallengeResponse? = {x in
            let response = x.structBody()
            let challenge = response?["challenge"]?.stringBody()
            let expireTime = response?["expire_time"]?.intBody()?.dateFromUnixSeconds()
            let serverTime = response?["server_time"]?.intBody()?.dateFromUnixSeconds()
            if challenge == nil || expireTime == nil && serverTime == nil {
                return nil
            }
            return GetChallengeResponse(challenge : challenge!, expireTime : expireTime!, serverTime : serverTime!)
        }
        return (XMLRPCURLRequest(name: "getchallenge", params: [:]), wrapXMLRPCParser(parser))
    }

    struct LoginResponse {
        let fullname : String
    }

    func login() -> Request<LoginResponse, ChallengeInfo> {
        let parser : XMLRPCParam -> LoginResponse? = {x in
            let response = x.structBody()
            let fullname = response?["fullname"]?.stringBody()
            if fullname == nil {
                return nil
            }
            return LoginResponse(fullname : fullname!)
        }

        // TODO all the login options
        return authenticatedXMLRPCRequest(name: "login", params: [:], parser: parser)
    }
    
    enum SyncAction {
        case Create
        case Update
        
        private static func from(#string : String) -> SyncAction? {
            switch(string) {
            case "create": return .Create
            case "update" : return .Update
            default: return nil
            }
        }
    }
    
    enum SyncType {
        case Journal
        case Comment
        
        private static func from(#string : String) -> SyncType? {
            switch(string) {
            case "C" : return .Comment
            case "L" : return .Journal
            default : return nil
            }
        }
    }
    
    
    struct SyncItem {
        let action : SyncAction
        let item : (type : SyncType, index : Int32)
        let time : NSDate
        
        private static func from(#param : XMLRPCParam) -> SyncItem? {
            let body = param.structBody()?
            let action = body?["action"]?.stringBody().bind{ SyncAction.from(string: $0) }
            let itemParam = body?["item"]?.stringBody()
            let itemParts = itemParam.bind{i -> [String]? in
                let components = (i as NSString).componentsSeparatedByString("-") as [String]
                return components.count == 2 ? components : nil
            }
            let item : (type : SyncType, index : Int32)? = itemParts.bind {components in
                return SyncType.from(string : components[0])
                .bind {t in
                    let index = (components[1] as NSString).intValue
                    return (type : t, index : index)
                }
                
            }
            let time : NSDate? = body?["time"]?.stringBody().bind{d in return DateUtils.standardFormatter.dateFromString(d)}
            if(item == nil || action == nil || time == nil) {
                return nil
            }
            return SyncItem(action: action!, item: item!, time: time!)
        }
    }
    
    struct SyncItemsResponse {
        let syncitems : [SyncItem]
        let count : Int32
        let total : Int32

    }
    
    func syncitems(lastSync : NSDate? = nil) -> Request<SyncItemsResponse, ChallengeInfo> {
        let parser : XMLRPCParam -> SyncItemsResponse? = {x in
            let response = x.structBody()
            let total = response?["total"]?.intBody()
            let count = response?["count"]?.intBody()
            let syncItemsBody = response?["syncitems"]?.arrayBody()
            let syncitems : [SyncItem]? = syncItemsBody?.mapOrFail{p in
                return SyncItem.from(param : p)
            }
            if total == nil || count == nil || syncitems == nil {
                return nil
            }
            return SyncItemsResponse(syncitems: syncitems!, count: count!, total: total!)
        }
        var params : [String : XMLRPCParam] = [:]
        if let d = lastSync {
            params["lastsync"] = XMLRPCParam.XString(DateUtils.stringFromDate(d))
        }
        
        return authenticatedXMLRPCRequest(name: "syncitems", params : params, parser : parser)
    }
    
    struct Friend {
        let user : String
        let name : String?
    }
    
    struct GetFriendsResponse {
        let friends : [Friend]
    }

    func getfriends() -> Request<GetFriendsResponse, ChallengeInfo> {
        let parser : XMLRPCParam -> GetFriendsResponse? = {x in
            let response = x.structBody()
            let friends : [Friend]? = response?["friends"]?.arrayBody()?.mapOrFail {b in
                let user = b.structBody()?["username"]?.stringBody()
                let name = b.structBody()?["fullname"]?.stringBody()
                return user.map {
                    return Friend(user : $0, name : name)
                }
            }
            return friends.map {
                GetFriendsResponse(friends : $0)
            }
        }
        return authenticatedXMLRPCRequest(name: "getfriends", params: [:], parser: parser)
    }

    struct Entry {
        let title : String?
        let author : String
        let date : NSDate
    }
    
    struct FeedResponse {
        let entries : [Entry]
    }

    func feedURL(#username : String) -> NSURL {
        let args = "auth=digest"
        if countElements(username) > 0 && username.hasPrefix("_") {
            return NSURL(scheme: "https", host:"users.livejournal.com", path:"\(username)/data/rss\(args)")!
        }
        else {
            return NSURL(scheme: "https", host:"\(username).livejournal.com", path:"/data/rss\(args)")!
        }
    }

    func feed(username : String) -> Request<FeedResponse, AuthSessionInfo> {
        let generator = {(sessionInfo : AuthSessionInfo) -> NSURLRequest in
            let url = self.feedURL(username : sessionInfo.username)
            return NSURLRequest(URL:url)
        }
        
        let parser = {(data : NSData) -> Result<FeedResponse> in
            let document = XMLParser().parse(data)
            println("document is \(document)")
            return Success(FeedResponse(entries:[]))
        }
        return Request(urlRequest : generator, parser : parser)
    }

}


protocol LJServiceOwner {
    var ljservice : LJService {get}
}
