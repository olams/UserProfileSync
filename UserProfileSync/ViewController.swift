//
//  ViewController.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 14.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

//
// Things to read
// 1. https://developer.apple.com/library/content/documentation/DataManagement/Conceptual/CloudKitQuickStart/MaintainingaLocalCacheofCloudKitRecords/MaintainingaLocalCacheofCloudKitRecords.html
// 2: Watch this
//    https://developer.apple.com/videos/play/wwdc2015/226/

import UIKit
import CloudKit
import CoreData

class ViewController: UITableViewController {

    @IBOutlet weak var syncObjects: UIBarButtonItem!

    let profiles = [
        "Profile 1",
        "Profile 2",
        "Profile 3",
        "Profile 4",
        "Profile 5",
        "Profile 6",
        "Profile 7"]
    
    @IBOutlet weak var newProfileButton: UIBarButtonItem!
    var persistenceContainer:NSPersistentContainer!
    var result: [UserProfile] = []
    
    var privateDB:CKDatabase!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        let container = CKContainer.default()
        privateDB = container.privateCloudDatabase
        
        if  persistenceContainer == nil {
            persistenceContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
        }
        
        //self.tableView.delegate = self
        //self.tableView.dataSource  = self
        // self.tableView.reloadData()
        // Do any additional setup after loading the view, typically from a nib.

        NotificationCenter.default.addObserver(self, selector: #selector(dataChanged(_:)), name: Notification.Name.NSManagedObjectContextDidSave, object: nil)
        
        self.updateView {
            
            // Done
        }
    }
    
    @objc func dataChanged(_ notification:Notification) {

        DispatchQueue.main.async {
            self.persistenceContainer.viewContext.mergeChanges(fromContextDidSave: notification)
            self.updateView() {}
        }
    }
    
    // MARK: Actions
    @IBAction func editProfiles(_ sender: Any) {
        self.tableView.setEditing(true, animated: true)
    }

    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        
        if editingStyle == .delete {
            
            tableView.beginUpdates()
            let userProfile = result[indexPath.row]
            result.remove(at: indexPath.row)

            persistenceContainer.viewContext.delete(userProfile)
            try! persistenceContainer.viewContext.save()
            self.tableView.deleteRows(at: [indexPath], with: .automatic)
            tableView.endUpdates()
            
            self.toggleButtons()
        }
    }

    @IBAction func newProfile(_ sender: Any) {
        self.createNewProfile(completitionHandler: nil)
    }

    func createNewProfile(completitionHandler: (() -> ())?) {
        
        let profile = UserProfile(context: persistenceContainer.viewContext)
        profile.objectID.uriRepresentation()
        profile.uuid = UUID()
        
        let existingProfileNames = result.map { return $0.name }
        let availableProfileNames = self.profiles.filter {
            return existingProfileNames.contains($0) == false
        }
        if availableProfileNames.count > 0 {
            profile.name = availableProfileNames.first
            try! persistenceContainer.viewContext.save()
            updateView(completitionHandler: completitionHandler)
        }
        
    }
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func toggleButtons() {
        newProfileButton.isEnabled = self.result.count < self.profiles.count
    }
    
    func updateView(completitionHandler: (() -> ())?) {
        
        let viewContext = persistenceContainer.viewContext
        
        viewContext.perform {
            self.result =  try! viewContext.fetch(UserProfile.fetchRequest())
            self.tableView.reloadData()
            self.toggleButtons()
            
            if let c = completitionHandler { c() }
        }
    }
    
    @IBAction func downloadChanges(_ sender: Any) {
        let syncManager = (UIApplication.shared.delegate as! AppDelegate).syncManager
        syncManager?.fetchChangesFromCloudKit { (result) in
            print("Changes from CloudKit: %@", result)
        }
    }
    
    @IBAction func uploadChanges(_ sender: Any) {
        
        let syncManager = (UIApplication.shared.delegate as! AppDelegate).syncManager
        syncManager?.sync { (count) in
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let up = result[indexPath.row]
        cell.textLabel?.text = up.name
        cell.detailTextLabel?.text = "\(up.uuid!.uuidString) "
            + (up.encodedSystemFields != nil ? " (Synced) ": "(Not Synced)" )
        return cell
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return result.count
    }

}
