/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Foundation
import Shared
import WebKit
import Strings
import os.log

/// Properties we want to extract from Tab/TabManager and save in TabMO
public struct SavedTab {
  public let id: String
  public let title: String?
  public let url: String
  public let isSelected: Bool
  public let order: Int16
  public let screenshot: UIImage?
  public let history: [String]
  public let historyIndex: Int16
  public let isPrivate: Bool

  /// For the love of all developers everywhere, if you use this constructor, **PLEASE** use
  /// `SessionData.updateSessionURLs(urls)` **BEFORE** passing in the URLs for the `history` parameter!!!
  /// If you don't, you **WILL break session restore**.
  public init(
    id: String, title: String?, url: String, isSelected: Bool, order: Int16, screenshot: UIImage?,
    history: [String], historyIndex: Int16, isPrivate: Bool) {
      self.id = id
      self.title = title
      self.url = url
      self.isSelected = isSelected
      self.order = order
      self.screenshot = screenshot
      self.history = history
      self.historyIndex = historyIndex
      self.isPrivate = isPrivate
      
  }
}

public final class TabMO: NSManagedObject, CRUD {

  @NSManaged public var title: String?
  @NSManaged public var url: String?
  @NSManaged public var syncUUID: String?
  @NSManaged public var order: Int16
  @NSManaged public var urlHistorySnapshot: NSArray?  // array of strings for urls
  @NSManaged public var urlHistoryCurrentIndex: Int16
  @NSManaged public var screenshot: Data?
  @NSManaged public var isSelected: Bool
  @NSManaged public var color: String?
  @NSManaged public var screenshotUUID: String?
  /// Last time this tab was updated. Required for 'purge unused tabs' feature.
  @NSManaged public var lastUpdate: Date?
  @NSManaged public var isPrivate: Bool
  
  public override func prepareForDeletion() {
    super.prepareForDeletion()
  }

  // MARK: - Public interface
  
  public static func migrate(_ block: @escaping (NSManagedObjectContext) -> Void) {
    DataController.performOnMainContext(save: true) { context in
      block(context)
      
      do {
        try context.save()
      } catch {
        Logger.module.error("Error saving context: \(error)")
      }
    }
  }

  // MARK: Create

  /// Creates new tab and returns its syncUUID. If you want to add urls to existing tabs use `update()` method.
  public class func create(title: String, uuidString: String = UUID().uuidString) -> String {
    createInternal(uuidString: uuidString, title: title, lastUpdateDate: Date())
    return uuidString
  }

  class func createInternal(uuidString: String, title: String, lastUpdateDate: Date) {
    DataController.perform(task: { context in
      guard let entity = entity(context) else {
        Logger.module.error("Error fetching the entity 'Tab' from Managed Object-Model")
        return
      }
      
      let tab = TabMO(entity: entity, insertInto: context)
      // TODO: replace with logic to create sync uuid then buble up new uuid to browser.
      tab.syncUUID = uuidString
      tab.title = title
      tab.lastUpdate = lastUpdateDate
    })
  }

  // MARK: Read

  public class func getAll() -> [TabMO] {
    let sortDescriptors = [NSSortDescriptor(key: #keyPath(TabMO.order), ascending: true)]
    return all(sortDescriptors: sortDescriptors) ?? []
  }

  public class func all(noOlderThan timeInterval: TimeInterval) -> [TabMO] {
    let lastUpdateKeyPath = #keyPath(TabMO.lastUpdate)
    let date = Date().advanced(by: -timeInterval) as NSDate
  
    let sortDescriptors = [NSSortDescriptor(key: #keyPath(TabMO.order), ascending: true)]
    let predicate = NSPredicate(format: "\(lastUpdateKeyPath) = nil OR \(lastUpdateKeyPath) > %@", date)
    return all(where: predicate, sortDescriptors: sortDescriptors) ?? []
  }

  public class func get(fromId id: String?) -> TabMO? {
    return getInternal(fromId: id)
  }
  
  // MARK: Update

  // Updates existing tab with new data.
  // Usually called when user navigates to a new website for in his existing tab.
  public class func update(tabData: SavedTab) {
    DataController.perform { context in
      guard let tabToUpdate = getInternal(fromId: tabData.id, context: context) else { return }

      if let screenshot = tabData.screenshot {
        tabToUpdate.screenshot = screenshot.jpegData(compressionQuality: 1)
      }
      tabToUpdate.url = tabData.url
      tabToUpdate.order = tabData.order
      tabToUpdate.title = tabData.title
      tabToUpdate.urlHistorySnapshot = tabData.history as NSArray
      tabToUpdate.urlHistoryCurrentIndex = tabData.historyIndex
      tabToUpdate.isSelected = tabData.isSelected
      tabToUpdate.lastUpdate = Date()
      tabToUpdate.isPrivate = tabData.isPrivate
    }
  }

  // Updates Tab's last accesed time.
  public class func touch(tabID: String) {
    DataController.perform { context in
      guard let tabToUpdate = getInternal(fromId: tabID, context: context) else { return }
      tabToUpdate.lastUpdate = Date()
    }
  }

  public class func selectTabAndDeselectOthers(selectedTabId: String) {
    DataController.perform { context in
      guard let tabToUpdate = getInternal(fromId: selectedTabId, context: context) else { return }

      let predicate = NSPredicate(format: "isSelected == true")
      all(where: predicate, context: context)?
        .forEach {
          $0.isSelected = false
        }

      tabToUpdate.isSelected = true
    }
  }

  // Deletes the Tab History by removing items except the last one from historysnapshot and setting current index
  public class func removeHistory(with tabID: String) {
    DataController.perform { context in
      guard let tabToUpdate = getInternal(fromId: tabID, context: context) else { return }

      if let lastItem = tabToUpdate.urlHistorySnapshot?.lastObject {
        tabToUpdate.urlHistorySnapshot = [lastItem] as NSArray
        tabToUpdate.urlHistoryCurrentIndex = 0
      }
    }
  }

  public class func saveScreenshotUUID(_ uuid: UUID?, tabId: String?) {
    DataController.perform { context in
      let tabMO = getInternal(fromId: tabId, context: context)
      tabMO?.screenshotUUID = uuid?.uuidString
    }
  }
  
  public class func saveTabOrder(tabIds: [String]) {
    DataController.perform { context in
      for (i, tabId) in tabIds.enumerated() {
        guard let managedObject = getInternal(fromId: tabId, context: context) else {
          Logger.module.error("Error: Tab missing managed object")
          continue
        }
        managedObject.order = Int16(i)
      }
    }
  }

  // MARK: Delete

  public func delete() {
    delete(context: .new(inMemory: false))
  }

  public class func deleteAll() {
    deleteAll(context: .new(inMemory: false))
  }

  public class func deleteAllPrivateTabs() {
    deleteAll(predicate: NSPredicate(format: "isPrivate == true"), context: .new(inMemory: false))
  }

  public class func deleteAll(olderThan timeInterval: TimeInterval) {
    let lastUpdateKeyPath = #keyPath(TabMO.lastUpdate)
    let date = Date().advanced(by: -timeInterval) as NSDate

    let predicate = NSPredicate(format: "\(lastUpdateKeyPath) != nil AND \(lastUpdateKeyPath) < %@", date)

    self.deleteAll(predicate: predicate)
  }
}

// MARK: - Internal implementations
extension TabMO {
  // Currently required, because not `syncable`
  private static func entity(_ context: NSManagedObjectContext) -> NSEntityDescription? {
    return NSEntityDescription.entity(forEntityName: "TabMO", in: context)
  }

  private class func getInternal(
    fromId id: String?,
    context: NSManagedObjectContext = DataController.viewContext
  ) -> TabMO? {
    guard let id = id else { return nil }
    let predicate = NSPredicate(format: "\(#keyPath(TabMO.syncUUID)) == %@", id)

    return first(where: predicate, context: context)
  }

  var imageUrl: URL? {
    if let objectId = self.syncUUID, let url = URL(string: "https://imagecache.mo/\(objectId).png") {
      return url
    }
    return nil
  }
}
