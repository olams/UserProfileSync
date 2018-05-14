//
//  ViewController.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 14.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import UIKit

class ViewController: UITableViewController {

    let profiles = [
        "Profile 1",
        "Profile 2",
        "Profile 3",
        "Profile 4",
        "Profile 5",
        "Profile 6",
        "Profile 7"]
    
    @IBOutlet weak var newProfileButton: UIBarButtonItem!
    let persistenceContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer
    var result:[UserProfile] = []
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //self.tableView.delegate = self
        //self.tableView.dataSource  = self
        // self.tableView.reloadData()
        // Do any additional setup after loading the view, typically from a nib.

        self.navigationItem.leftBarButtonItem = self.editButtonItem
        self.updateView()
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
        let profile = UserProfile(context: persistenceContainer.viewContext)
        let existingProfileNames = result.map { return $0.name }
        let availableProfileNames = self.profiles.filter {
            return existingProfileNames.contains($0) == false
        }
        if availableProfileNames.count > 0 {
            profile.name = availableProfileNames.first
            try! persistenceContainer.viewContext.save()
            updateView()
        }
    }

    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    func toggleButtons() {
        newProfileButton.isEnabled = self.result.count < self.profiles.count
    }
    
    func updateView() {
        
        let viewContext = persistenceContainer.viewContext
        viewContext.perform {
            self.result =  try! viewContext.fetch(UserProfile.fetchRequest())
            self.tableView.reloadData()
            self.toggleButtons()
        }
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = result[indexPath.row].name
        return cell
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return result.count
    }

}
