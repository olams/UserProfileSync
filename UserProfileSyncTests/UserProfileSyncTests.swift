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
    
    override func setUp() {
        super.setUp()
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

    func testCreateUserProfile() {
        
        let e = expectation(description: "Should create user profile")
        let vc = createViewController()
        
        vc.createNewProfile {
            XCTAssertEqual(vc.result.count, 1)
            e.fulfill()
        }
        self.waitForExpectations(timeout: 10, handler: nil)
    }
    
    
    func testSyncUserProfiles() {
        
        let syncmanager = (UIApplication.shared.delegate as! AppDelegate).syncManager
        
        let e = expectation(description: "Should sync user profiles")
        let vc = createViewController()

        vc.createNewProfile {
            
            syncmanager?.sync {
                
                e.fulfill()
            }
        }
        waitForExpectations(timeout: 10, handler: nil)
    }
    
    
    func testCloudKitCreateUserProfilInCloud() {
        
        let e = expectation(description: "CreateUserProfileInCloud")
        let syncmanager = (UIApplication.shared.delegate as! AppDelegate).syncManager
        let pcm = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
        let context = pcm.viewContext
        let userProfile = UserProfile(context: context)
        userProfile.name = "Unit Test"
        syncmanager?.createOrUpdateObject(userProfile: userProfile) {
            
            e.fulfill()
        }
        
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



