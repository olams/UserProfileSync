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

enum SyncMethod : String {
    case post = "post"
    case delete = "delete"
}

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

protocol Syncable {
    var encodedSystemFields:String? { get }
}

class SyncManager {
    
    let persistenceContainer:NSPersistentContainer
    let privateDB = CKContainer(identifier: "iCloud.SAGLI.ICloudSync").privateCloudDatabase
    let syncContext:NSManagedObjectContext!
    
    init(persistenceContainer:NSPersistentContainer, mode:SyncManagerMode) {
        self.persistenceContainer = persistenceContainer
        
        // Use this for save / reading the SyncOperations
        syncContext = self.persistenceContainer.newBackgroundContext()
        
        // Kick of notification when automatic mode is enabled
        if mode == .automatic {
            NotificationCenter.default.addObserver(self, selector: #selector(handleSave(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: nil)
        }

    }
    
    @objc func handleSave(_ notification: Notification) {

        let userInfo = notification.userInfo!

        let context = notification.object as! NSManagedObjectContext
        
        if context == self.syncContext {
            return
        }

        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<UserProfile> {
            addToSyncOperationInserts(userProfiles: inserts)
        }
    
        if let delets = userInfo[NSDeletedObjectsKey] as? Set<UserProfile> {
            addToSyncOperationToDeletes(userProfiles: delets)
        }
    }
    
    // MARK:- CRUD Operations -
    func addToSyncOperationToDeletes(userProfiles:Set<UserProfile>) {
        
        for userProfile in userProfiles {

            // Cannot delete if we dont have the encode system fields
            guard let encodeSystemFields = userProfile.encodeSystemFields else {
                continue
            }
            
            let syncOperation = SyncOperation(context: syncContext)
            syncOperation.method = SyncMethod.delete.rawValue
            syncOperation.encodedSystemFields = encodeSystemFields
        }
        try! syncContext.save()
    }
    
    func addToSyncOperationInserts(userProfiles:Set<UserProfile>) {

        for userProfile in userProfiles {
            let syncOperation = SyncOperation(context: syncContext)
            syncOperation.uri = userProfile.objectID.uriRepresentation()
            syncOperation.method = SyncMethod.post.rawValue
            syncOperation.uuid = userProfile.uuid
        }
        print("Added \(userProfiles.count) to sync operations" )
        try! syncContext.save()
    }
    
    func sync(completition: ((Result<Int>) -> Void)?) {
        
        
        syncContext.perform {
            
            let result = try! self.syncContext.fetch(SyncOperation.fetchRequest()) as [SyncOperation]
            print("Result is \(result)")

            for u in result {
                
                let method = SyncMethod(rawValue: u.method!)
                if method == .post {
                    
                    guard let uri = u.uri else { continue }
                    let managedID = self.syncContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)!

                    do {
                        if let userProfile = self.syncContext.object(with: managedID!) as? UserProfile {
                            self.createOrUpdateObject(userProfile: userProfile) { (result) in }
                        }
                    } catch {
                        print("Error loading \(error)")
                    }
                }
                
                else if method == .delete {
                    
                    let record = self.createCKRecordFromEncodedSystemFields(encodedSystemFields: u.encodedSystemFields!)
                    self.privateDB.delete(withRecordID: record.recordID, completionHandler: { (recordId, error) in
                        
                    })
                }
            }
            
            if let completition = completition {
                completition(Result.Success(result.count))
            }
            
            // Clean up
            for u in result {
                self.syncContext.delete(u)
            }
            try! self.syncContext.save()
        }
    }
    
    func createOrUpdateObject(userProfile:UserProfile, completition:@escaping (Result<UserProfile>) -> Void) {

        var record:CKRecord!
        
        if let archivedData = userProfile.encodeSystemFields {
            record = createCKRecordFromEncodedSystemFields(encodedSystemFields: archivedData)
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
            
            if userProfile.encodeSystemFields == nil {
            // Get record back
            let data = NSMutableData()
            let coder = NSKeyedArchiver.init(forWritingWith: data)
            coder.requiresSecureCoding = true
            record!.encodeSystemFields(with: coder)
            coder.finishEncoding()

            let userProfileSave = self.syncContext.object(with: userProfile.objectID) as! UserProfile
            userProfileSave.encodeSystemFields = data as Data
            do {
                try self.syncContext.save()
            } catch {
                fatalError(error.localizedDescription)
                return
            }
            }
            DispatchQueue.main.async {
                completition(Result.Success(userProfile))
            }
       }
    }
    
    func createCKRecordFromEncodedSystemFields(encodedSystemFields:Data) -> CKRecord {
        let unarchiver = NSKeyedUnarchiver(forReadingWith: encodedSystemFields)
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)!
    }
}
