//
//  SyncManager.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 16.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import Foundation
import CoreData
import CloudKit
import UIKit

let SyncActionPost = "POST"
let SyncActionDelete = "DELETE"

// Globals
let NOTIFICATION_SYNC_POST = "syncPost"

class SyncManager {
    
    let persistenceContainer:NSPersistentContainer
    let privateDB = CKContainer(identifier: "iCloud.SAGLI.ICloudSync").privateCloudDatabase

    init(persistenceContainer:NSPersistentContainer) {
        self.persistenceContainer = persistenceContainer
        NotificationCenter.default.addObserver(self, selector: #selector(handleSave(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: nil)
    }
    
    @objc func handleSave(_ notification: Notification) {

        let persistenceContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
        let userInfo = notification.userInfo!

        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<UserProfile> {
            let backgroundContext = persistenceContainer.newBackgroundContext()
            for userProfile in inserts {
                let syncOperation = SyncOperation(context: backgroundContext)
                syncOperation.uri = userProfile.objectID.uriRepresentation()
                syncOperation.method = SyncActionPost
                syncOperation.uuid = userProfile.uuid
                try! backgroundContext.save()
            }
        }
    }
    
    func sync(completitionHandler: (() -> ())?) {
        
        let context = persistenceContainer.newBackgroundContext()
        
        context.perform {
            
            let result = try! context.fetch(SyncOperation.fetchRequest()) as [SyncOperation]
            print("Result : \(result)")
            
            for u in result {
                if let uri = u.uri  {
                    
                    let managedID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)!
                    let userProfile = context.object(with: managedID!) as! UserProfile
                    
                    self.createOrUpdateObject(userProfile: userProfile) {
                    }
                    print("Got the id: \(userProfile.name)")
                }
            }
            if let c = completitionHandler { c() }
        }
    }
    
    func createOrUpdateObject(userProfile:UserProfile, completitionHandler:@escaping () -> ()) {

        var record:CKRecord!
        
        if let archivedData = userProfile.encodeSystemFields {
            let unarchiver = NSKeyedUnarchiver(forReadingWith: archivedData)
            unarchiver.requiresSecureCoding = true
            record = CKRecord(coder: unarchiver)
        } else {
            record = CKRecord(recordType: "UserProfiles")
        }
        record["name"] = userProfile.name! as NSString

        self.privateDB.save(record) { (record, error) in
            
            if (error != nil) {
                print("Error: \(error?.localizedDescription)")
                completitionHandler()
                return
            }
            
            // Get record back
            let data = NSMutableData()
            let coder = NSKeyedArchiver.init(forWritingWith: data)
            coder.requiresSecureCoding = true
            record!.encodeSystemFields(with: coder)
            coder.finishEncoding()

            userProfile.encodeSystemFields = data as Data
            try! userProfile.managedObjectContext!.save()
            
            completitionHandler()
       }
    }
}
