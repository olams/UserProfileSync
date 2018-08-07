//
//  UserProfileSyncTests.swift
//  UserProfileSyncTests
//
//  Created by Ola Marius Sagli on 14.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import XCTest
import CloudKit
import CoreData

@testable import UserProfileSync


class UserProfileSyncTests: XCTestCase {
    
    var syncManager:SyncManager!
    var persistentContainer:NSPersistentContainer!
    
    override func setUp() {
        super.setUp()
        
        persistentContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
        syncManager = SyncManager(persistenceContainer: persistentContainer, mode: .manual)
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    // MARK:- Helper methods
    func createCXRecord() -> CKRecord {
        
        let zoneID = CKRecordZoneID(zoneName: "UserProfileZone", ownerName: CKCurrentUserDefaultName)
        let recordID = CKRecordID(recordName: UUID().uuidString, zoneID: zoneID)
        let record = CKRecord(recordType: "UserProfiles", recordID: recordID)
        record["name"] = "CK Record Name" as! NSString
        return record
        
        
    }
    
    func createViewController() -> ViewController {
        
        let e = expectation(description: "Should create profile")
        let storyboard =  UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "ViewController") as! ViewController
        vc.view.isHidden = false
        return vc
    }
    
    // MARK:- Tests
    func testSyncUserProfiles() {
        
        let e = expectation(description: "Should sync user profiles")
      
        let userProfile = UserProfile(context: persistentContainer.viewContext)
        userProfile.uuid = UUID()
        userProfile.name = "Unit test"
        try! persistentContainer.viewContext.save()


        syncManager.addSyncOperationToInserts(managedObjects: [userProfile])
        
        syncManager.sync { (result) in
            switch result {
            case .Success(let count) :
                XCTAssertEqual(count, 1)
                self.persistentContainer.viewContext.refresh(userProfile, mergeChanges: true)
                XCTAssertNil(userProfile.encodedSystemFields)
            case .Failure(_):
                XCTFail()
            }
            e.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testUpdateFromCloudKit() {
        
        let e = expectation(description: "Update from cloud kit")
        let context = persistentContainer.viewContext
        
        let record1 = createCXRecord()

        // Save profile
        let userProfile = UserProfile(context: context)
        userProfile.uuid = UUID(uuidString: record1.recordID.recordName)
        try! context.save()
        
        self.syncManager.insertOrUpdateRecordFromCloudKit(record: record1) { (result) in
        
            switch result {
            
            case .Success(let method, let syncable):
                XCTAssertEqual(method, SyncMethod.update)
                e.fulfill()
            case .Failure(_):
                XCTFail()
            }
        }
        self.waitForExpectations(timeout: 10, handler: nil)
    }
    

    func testCloudKitCreateUserProfileInCloud() {
        
        let e = expectation(description: "CreateUserProfileInCloud")
        
        let context = persistentContainer.viewContext
        let userProfile = UserProfile(context: context)
        userProfile.uuid = UUID()
        userProfile.name = "Unit Test"

        try! context.save()
        
        syncManager.saveToCloudKit(syncable: userProfile, completition: { (result) in
            switch result {
            case .Success(let syncable):
                XCTAssertNotNil(syncable.encodedSystemFields)
                
                e.fulfill()
            case .Failure(_):
                XCTFail()
            }
        })
        waitForExpectations(timeout: 10, handler: nil)
    }

    func testInsertCXRecordFromCloudKit() {

        let e = expectation(description: "testInsertCXRecordFromCloudKit")

        let record = createCXRecord()
        
        syncManager.insertOrUpdateRecordFromCloudKit(record: record) { (result) in
            
            print("Record is", record)
            
            switch result {
                
            case .Success(let syncMethod, let record):
                XCTAssertEqual(syncMethod,.insert)
                e.fulfill()

            case .Failure(_):
                XCTFail()
            }
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCreaateCKRecordFromSyncable() {
        
        let userProfile = UserProfile(context: persistentContainer.viewContext)
        userProfile.uuid = UUID()
        userProfile.name = "test"
        
        let record = syncManager.creaateCKRecordFromSyncable(syncable: userProfile )
        XCTAssertEqual(record.recordID.recordName, userProfile.uuid?.uuidString)
    }
    
}



