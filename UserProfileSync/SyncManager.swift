//
//  SyncManager.swift
//  SyncableSync
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
    var recordType:String { get }
    var zoneName:String { get }
    var objectID:NSManagedObjectID { get }
    var encodedSystemFields:Data? { get set }
    func setCXRecordData(record:CKRecord)
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
            // This is internal stuff so this is to avoid eternal looping
            return
        }
        
        if let inserts = userInfo[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            addToSyncOperationInserts(managedObjects: inserts)
        }
    
        if let delets = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            addToSyncOperationToDeletes(managedObjects: delets)
        }
    }
    
    // MARK:- CRUD Operations -
    func addToSyncOperationToDeletes(managedObjects:Set<NSManagedObject>) {
        
        for case let syncable as Syncable in managedObjects {

            // Cannot delete if we dont have the encode system fields
            guard let encodedSystemFields = syncable.encodedSystemFields else {
                continue
            }
            
            let syncOperation = SyncOperation(context: syncContext)
            syncOperation.method = SyncMethod.delete.rawValue
            syncOperation.encodedSystemFields = encodedSystemFields
        }
        try! syncContext.save()
    }
    
    func addToSyncOperationInserts(managedObjects:Set<NSManagedObject>) {

        for case let syncable as Syncable in managedObjects {
            
            let syncOperation = SyncOperation(context: syncContext)
            syncOperation.uri = syncable.objectID.uriRepresentation()
            syncOperation.method = SyncMethod.post.rawValue
        }
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
                        if let Syncable = self.syncContext.object(with: managedID!) as? Syncable {
                            self.createOrUpdateObject(syncable: Syncable) { (result) in }
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
    
    func createOrUpdateObject(syncable:Syncable, completition:@escaping (Result<Syncable>) -> Void) {

        var record:CKRecord!
        
        if let archivedData = syncable.encodedSystemFields {
            record = createCKRecordFromEncodedSystemFields(encodedSystemFields: archivedData)
        } else {
            let zoneID = CKRecordZoneID(zoneName: syncable.zoneName, ownerName: CKCurrentUserDefaultName)
            record = CKRecord(recordType: syncable.recordType, zoneID: zoneID)
        }
        syncable.setCXRecordData(record: record)
        
        self.privateDB.save(record) { (record, error) in
            
            if (error != nil) {
                DispatchQueue.main.async {
                    completition(Result.Failure(error!))
                }
                return
            }
            
            if syncable.encodedSystemFields == nil {
                // Get record back
                let data = NSMutableData()
                let coder = NSKeyedArchiver.init(forWritingWith: data)
                coder.requiresSecureCoding = true
                record!.encodeSystemFields(with: coder)
                coder.finishEncoding()

                var syncSaveObject = self.syncContext.object(with: syncable.objectID) as! Syncable
                syncSaveObject.encodedSystemFields = data as Data
                do {
                    try self.syncContext.save()
                } catch {
                    fatalError(error.localizedDescription)
                    return
                }
            }
            DispatchQueue.main.async {
                completition(Result.Success(syncable))
            }
       }
    }
    
    func createCKRecordFromEncodedSystemFields(encodedSystemFields:Data) -> CKRecord {
        let unarchiver = NSKeyedUnarchiver(forReadingWith: encodedSystemFields)
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)!
    }
    
    func fetchChangesFromCloudKit(completition:@escaping () -> Void) {

        let database = self.privateDB
        var changedZoneIDs: [CKRecordZoneID] = []
        
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: nil)
        
        operation.recordZoneWithIDChangedBlock = { (zoneID) in
            changedZoneIDs.append(zoneID)
        }
        
        operation.changeTokenUpdatedBlock = { (token) in
            
            
            // Flush zone deletions for this database to disk
            // Write this new database change token to memory
        }
        
        operation.fetchDatabaseChangesCompletionBlock = { (token, moreComing, error) in
            
            if let error = error {
                print(error.localizedDescription)
                return 
            }

            self.fetchZoneChanges(database: database, databaseTokenKey: "private", zoneIDs: changedZoneIDs) {
                // Flush in-memory database change token to disk
                completition()
            }
        }
        database.add(operation)
    }
    
    func fetchZoneChanges(database: CKDatabase, databaseTokenKey: String, zoneIDs: [CKRecordZoneID], completion: @escaping () -> Void) {
        
        print("ZoneIDs: ", zoneIDs)
        
        // Look up the previous change token for each zone
        var optionsByRecordZoneID = [CKRecordZoneID: CKFetchRecordZoneChangesOptions]()
        for zoneID in zoneIDs {
            let options = CKFetchRecordZoneChangesOptions()
            // options.previousServerChangeToken = … // Read change token from disk
                optionsByRecordZoneID[zoneID] = options
            
            
        }
        
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: optionsByRecordZoneID)
        
        operation.recordChangedBlock = { (record) in
            print("@@@@@@@@@@@@ Record changed:", record)
            // Write this record change to memory
        }
        
        operation.recordZoneChangeTokensUpdatedBlock = { (zoneId, token, data) in
            // Flush record changes and deletions for this zone to disk
            // Write this new zone change token to disk
            print("@@@@@@@@@@@@@@@ New token for zoneId: \(zoneId) token:\(token)")
        }
        
        operation.recordZoneFetchCompletionBlock = { (zoneId, changeToken, _, _, error) in
            if let error = error {
                print("Error fetching zone changes for \(databaseTokenKey) database:", error)
                return
            }
            print("New change token: \(zoneId)")
            // Flush record changes and deletions for this zone to disk
            // Write this new zone change token to disk
        }
        
        operation.fetchRecordZoneChangesCompletionBlock = { (error) in
            if let error = error {
                print("Error fetching zone changes for \(databaseTokenKey) database:", error)
            }
            completion()
        }
        
        database.add(operation)
    }
}
