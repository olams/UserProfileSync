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

enum Result<T> {
    case Success(T)
    case Failure(Error)
}

enum SyncManagerMode {
    case automatic
    case manual
}

class SyncManager {
    
    let persistenceContainer:NSPersistentContainer
    let privateDB = CKContainer(identifier: "iCloud.SAGLI.ICloudSync").privateCloudDatabase

    init(persistenceContainer:NSPersistentContainer, mode:SyncManagerMode) {
        self.persistenceContainer = persistenceContainer
        
        // Kick of notification when automatic mode is enabled
        if mode == .automatic {
            NotificationCenter.default.addObserver(self, selector: #selector(handleSave(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: nil)
        }
    }
    
    @objc func handleSave(_ notification: Notification) {

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
    
    func addToSyncOperation(userProfiles:[UserProfile]) {

        let backgroundContext = persistenceContainer.newBackgroundContext()

        for userProfile in userProfiles {
            let syncOperation = SyncOperation(context: backgroundContext)
            syncOperation.uri = userProfile.objectID.uriRepresentation()
            syncOperation.method = SyncActionPost
            syncOperation.uuid = userProfile.uuid
        }
        print("Added \(userProfiles.count) to sync operations" )
        try! backgroundContext.save()
    }
    
    func sync(completition: ((Result<Int>) -> Void)?) {
        
        let context = persistenceContainer.newBackgroundContext()
        
        context.perform {
            
            let result = try! context.fetch(SyncOperation.fetchRequest()) as [SyncOperation]
            print("Result is \(result)")

            for u in result {
                
                if let uri = u.uri  {
                    
                    let managedID = context.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)!
                    do {
                        if let userProfile = context.object(with: managedID!) as? UserProfile {
                            self.createOrUpdateObject(userProfile: userProfile) { (result) in }
                        }
                    } catch {
                        print("Error loading \(error)")
                    }
                }
            }
            
            if let completition = completition {
                completition(Result.Success(result.count))
            }
        }
    }
    
    func createOrUpdateObject(userProfile:UserProfile, completition:@escaping (Result<UserProfile>) -> Void) {

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
                DispatchQueue.main.async {
                    completition(Result.Failure(error!))
                }
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
            
            DispatchQueue.main.async {
                completition(Result.Success(userProfile))
            }
       }
    }
}
