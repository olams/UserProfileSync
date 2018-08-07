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
    case insert = "insert"
    case update = "update"
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
    var uuid:UUID? { get }

    // CloudKit
    var ckRecordType:String { get }
    var ckZoneName:String { get }
    var encodedSystemFields:Data? { get set }

    // Core data id
    var objectID:NSManagedObjectID { get }

    // Convert data to / from cloud kit
    func updateCKRecord(record:CKRecord)
    func setData(record:CKRecord)
}

class SyncManager {
    
    let persistenceContainer:NSPersistentContainer
    let privateDB = CKContainer(identifier: "iCloud.SAGLI.ICloudSync").privateCloudDatabase
    let syncContext:NSManagedObjectContext!
    var lastServerChangeToken:CKServerChangeToken? = nil
    var lastZoneChangeTokens:[CKRecordZoneID:CKServerChangeToken] = [:]
    
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
            addSyncOperationToInserts(managedObjects: inserts)
        }
    
        if let delets = userInfo[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            addSyncOperationToDeletes(managedObjects: delets)
        }

        self.sync { (result) in
            
        }
    }
    
    // MARK:- CRUD Operations -
    func addSyncOperationToDeletes(managedObjects:Set<NSManagedObject>) {
        
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
    
    func addSyncOperationToInserts(managedObjects:Set<NSManagedObject>) {

        for case let syncable as Syncable in managedObjects {
            
            let syncOperation = SyncOperation(context: syncContext)
            syncOperation.uri = syncable.objectID.uriRepresentation()
            syncOperation.method = SyncMethod.insert.rawValue
        }
        try! syncContext.save()
    }
    
    func sync(completition: ((Result<Int>) -> Void)?) {
        
        syncContext.perform {
            
            let result = try! self.syncContext.fetch(SyncOperation.fetchRequest()) as [SyncOperation]
            print("Result is \(result)")

            for u in result {
                
                let method = SyncMethod(rawValue: u.method!)
                if method == .insert {
                    
                    guard let uri = u.uri else { continue }
                    let managedID = self.syncContext.persistentStoreCoordinator?.managedObjectID(forURIRepresentation: uri)!

                    if let syncable = self.syncContext.object(with: managedID!) as? Syncable {
                        self.saveToCloudKit(syncable: syncable) { (result) in }
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
    
    // MARK:- CX Records -
    func encodedSystemFields (record:CKRecord) -> Data {
        let data = NSMutableData()
        let coder = NSKeyedArchiver.init(forWritingWith: data)
        coder.requiresSecureCoding = true
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return data as Data
    }
    
    func creaateCKRecordFromSyncable(syncable:Syncable) -> CKRecord {
        let zoneID = CKRecordZoneID(zoneName: syncable.ckZoneName, ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecordID(recordName: syncable.uuid!.uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: syncable.ckRecordType, recordID: recordID)
        syncable.updateCKRecord(record: record)
        return record
    }
    
    func createCKRecordFromEncodedSystemFields(encodedSystemFields:Data) -> CKRecord {
        let unarchiver = NSKeyedUnarchiver(forReadingWith: encodedSystemFields)
        unarchiver.requiresSecureCoding = true
        return CKRecord(coder: unarchiver)!
    }
    
    
    func fetch(uuid:UUID, recordType:String) -> NSManagedObject? {
        let fetchRequest:NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        fetchRequest.predicate =  NSPredicate(format: "%K == %@", "uuid", uuid as CVarArg)
        let result = try! self.syncContext.fetch(fetchRequest)
        return result.first
    }
    
    // MARK: - Cloud Kit CRUD -
    func deleteRecordFromCloudKit(recordID:CKRecordID, recordType:String, completition: (Result<Syncable>) -> Void) {
        
        let uuid = UUID(uuidString: recordID.recordName)
        if let managedObject = fetch(uuid: uuid!, recordType: recordType) {
            
            syncContext.delete(managedObject)
            

            do {
                try syncContext.save()
                completition(Result.Success((managedObject as! Syncable)))
            } catch {
                completition(Result.Failure(error))
            }
        }
    }
    
    func insertOrUpdateRecordFromCloudKit(record:CKRecord, completition:@escaping (Result<(SyncMethod,Syncable)>) -> Void) {


        let uuid = UUID(uuidString: record.recordID.recordName)!

        syncContext.perform {
            
            do {
                if let syncable = self.fetch(uuid: uuid, recordType: "UserProfile") as? Syncable {
                    
                    print("UPDATE syncable with UUID %@", syncable.uuid!)
                    syncable.setData(record: record)
                    try self.syncContext.save()
                    completition(Result.Success((.update, syncable)))
                }
                else {
                    print("INSERT syncable with UUID %@", uuid)
                    let managedObject = UserProfile(context: self.syncContext)
                    managedObject.setData(record: record)
                    managedObject.uuid = uuid
                    managedObject.encodedSystemFields = self.encodedSystemFields(record: record)
                    try self.syncContext.save()
                    
                    completition(Result.Success((.insert, managedObject)))
                }

            } catch {
                completition(Result.Failure(error))
            }
        }
    }
    
    
    // MARK: - Cloud Kit Sync -
    func saveToCloudKit(syncable:Syncable, completition:@escaping (Result<Syncable>) -> Void) {
        
        var record:CKRecord!
        
        if let archivedData = syncable.encodedSystemFields {
            record = createCKRecordFromEncodedSystemFields(encodedSystemFields: archivedData)
        } else {
            record = creaateCKRecordFromSyncable(syncable: syncable)
        }
        
        self.privateDB.save(record) { (record, error) in
            
            if (error != nil) {
                print("Error saving record %@", error?.localizedDescription)
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
                }
            }
            DispatchQueue.main.async {
                completition(Result.Success(syncable))
            }
        }
    }
    
    func fetchChangesFromCloudKit(completition:@escaping (Result<Void>) -> Void) {

        let database = self.privateDB
        var changedZoneIDs: [CKRecordZoneID] = []
        
        let operation = CKFetchDatabaseChangesOperation(previousServerChangeToken: self.lastServerChangeToken)
        
        operation.recordZoneWithIDChangedBlock = { (zoneID) in
            changedZoneIDs.append(zoneID)
        }

        operation.changeTokenUpdatedBlock = { (token) in
            
            self.lastServerChangeToken = token
            // Flush zone deletions for this database to disk
            // Write this new database change token to memory
        }
        
        operation.fetchDatabaseChangesCompletionBlock = { (token, moreComing, error) in
            
            if let error = error {
                completition(Result.Failure(error))
                return 
            }
            
            self.fetchZoneChanges(database: database, databaseTokenKey: "private", zoneIDs: changedZoneIDs, completion: completition)
        }
        
        database.add(operation)
    }
    
    func fetchZoneChanges(database: CKDatabase, databaseTokenKey: String, zoneIDs: [CKRecordZoneID], completion: @escaping (Result<Void>) -> Void) {

        if zoneIDs.count == 0 {
            completion(Result.Success(()))
            return
        }
        print("Fetching zone with id " , zoneIDs)
        
        let fetchRequest:NSFetchRequest<UserProfile> = UserProfile.fetchRequest()
        let existingRecords = try! self.syncContext.fetch(fetchRequest)
        for s in existingRecords {
            print("Existing : %@ %@", s.uuid!.uuidString, (s.isDeleted ? "(deleted)" : " (Not deleted)"))
        }

        
        
        // Look up the previous change token for each zone
        var optionsByRecordZoneID = [CKRecordZoneID: CKFetchRecordZoneChangesOptions]()
        for zoneID in zoneIDs {
            let options = CKFetchRecordZoneChangesOptions()
            if let lastZoneChangeToken = lastZoneChangeTokens[zoneID] {
                options.previousServerChangeToken = lastZoneChangeToken
            }
            optionsByRecordZoneID[zoneID] = options
        }
        
        let operation = CKFetchRecordZoneChangesOperation(recordZoneIDs: zoneIDs, optionsByRecordZoneID: optionsByRecordZoneID)
        operation.recordChangedBlock = { (record) in
            print("CloudKit: Record change : ", record.recordID.recordName)
            self.insertOrUpdateRecordFromCloudKit(record: record, completition: { (result) in
                print("Inserted record from cloud")
            })
        }
        
        operation.recordWithIDWasDeletedBlock = { (recordID, recordType) in
            
            self.deleteRecordFromCloudKit(recordID: recordID, recordType:recordType, completition: { (result) in
                print("Record deleted:", recordID, " RecordType: ", recordType)
            })
                
            // Write this record deletion to memory
        }
        
        operation.recordZoneChangeTokensUpdatedBlock = { (zoneId, token, data) in
            
            self.lastZoneChangeTokens[zoneId] = token
            // Flush record changes and deletions for this zone to disk
            // Write this new zone change token to disk
            print("New token for zoneId: \(zoneId) token:\(token)")
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
            completion(Result.Success(()))
        }
        
        database.add(operation)
    }
}
