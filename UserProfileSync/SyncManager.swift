//
//  SyncManager.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 16.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import Foundation
import CoreData
import UIKit

class SyncManager {
    
    init() {
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
                syncOperation.method = NOTIFICATION_SYNC_POST
                try! backgroundContext.save()
                
                print("Insert \(userProfile.name)")
            }
        }
    }
}
