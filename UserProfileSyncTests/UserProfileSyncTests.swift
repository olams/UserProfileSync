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
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func createViewController() -> ViewController {
        
        let e = expectation(description: "Should create profile")
        let storyboard =  UIStoryboard(name: "Main", bundle: nil)
        let vc = storyboard.instantiateViewController(withIdentifier: "ViewController") as! ViewController
        vc.view.isHidden = false
        return vc
    }
    
    func testSyncUserProfiles() {
        
        let e = expectation(description: "Should sync user profiles")
      
        let userProfile = UserProfile(context: persistentContainer.viewContext)
        userProfile.name = "Unit test"
        try! persistentContainer.viewContext.save()
        
        syncManager.addToSyncOperation(userProfiles: [userProfile])
        
        syncManager.sync { (result) in
            switch result {
            case .Success(let count) : XCTAssertEqual(count, 1)
            case .Failure(_):
                XCTFail()
            }
            e.fulfill()
        }
        
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testCloudKitCreateUserProfilInCloud() {
        
        let e = expectation(description: "CreateUserProfileInCloud")
        
        let context = persistentContainer.viewContext
        let userProfile = UserProfile(context: context)
        userProfile.name = "Unit Test"
        
        syncManager.createOrUpdateObject(userProfile: userProfile, completition: { (result) in
            switch result {
            case .Success(let userProfile):
                e.fulfill()
            case .Failure(_):
                XCTFail()
            }
        })
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    func testExample() {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }
    
    func testPerformanceExample() {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }
    
}



