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
        
    var ckZoneName: String {
        get {
            return "UserProfileZone"
        }
    }
    
    var ckRecordType: String {
        get {
            return "UserProfiles"
        }
    }
    
   func updateCKRecord(record: CKRecord) {
        record["name"] = name! as NSString
    }
    
    func setData(record: CKRecord) {
        self.name = record["name"] as! String
    }
    
}
