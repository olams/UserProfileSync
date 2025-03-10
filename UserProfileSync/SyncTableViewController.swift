//
//  SyncTableViewController.swift
//  UserProfileSync
//
//  Created by Ola Marius Sagli on 16.05.2018.
//  Copyright © 2018 Ola Marius Sagli. All rights reserved.
//

import UIKit

class SyncTableViewController: UITableViewController {

    var result:[SyncOperation] = []
    let persistenceContainer = (UIApplication.shared.delegate as! AppDelegate).persistentContainer

    override func viewDidLoad() {
        super.viewDidLoad()

        // Uncomment the following line to preserve selection between presentations
        // self.clearsSelectionOnViewWillAppear = false

        // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
        // self.navigationItem.rightBarButtonItem = self.editButtonItem
        self.updateView()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }

    // MARK: - Table view data source

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        // #warning Incomplete implementation, return the number of rows
        return result.count
    }

    func updateView() {
        let viewContext = persistenceContainer.viewContext
        viewContext.perform {
            self.result =  try! viewContext.fetch(SyncOperation.fetchRequest())
            self.tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let syncOperation = result[indexPath.row]
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        let syncManager = (UIApplication.shared.delegate as! AppDelegate).syncManager
    
        if let esf = syncOperation.encodedSystemFields {
            let record = syncManager?.createCKRecordFromEncodedSystemFields(encodedSystemFields: esf)
            cell.textLabel?.text =  record!.recordID.recordName
        } else {
            cell.textLabel?.text = syncOperation.uri?.absoluteString
        }
        cell.detailTextLabel?.text = syncOperation.method
        return cell
    }

    
    
    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
