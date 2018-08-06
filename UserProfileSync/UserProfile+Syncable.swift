//
//  UserProfile+Syncable.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 28.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import Foundation
import CloudKit

extension UserProfile : Syncable {
        
    var zoneName: String {
        get {
            return "UserProfileZone"
        }
    }
    
    var recordType: String {
        get {
            return "UserProfiles"
        }
    }
    
   func setCXRecordData(record: CKRecord) {
        record["name"] = name! as NSString
    }
    
    func setData(record: CKRecord) {
        self.name = record["name"] as! String
    }
    
}
