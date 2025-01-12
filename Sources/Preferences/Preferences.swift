/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import os.log
import Combine

/// An empty protocol simply here to force the developer to use a user defaults encodable value via generic constraint
public protocol UserDefaultsEncodable {}

/// The applications preferences container
///
/// Properties in this object should be of the the type `Option` with the object which is being
/// stored to automatically interact with `UserDefaults`
public class Preferences {
  /// The default `UserDefaults` that all `Option`s will use unless specified
  public static let defaultContainer = UserDefaults(suiteName: AppInfo.sharedContainerIdentifier)!
}

/// Defines an object which may watch a set of `Preference.Option`s
/// - note: @objc was added here due to a Swift compiler bug which doesn't allow a class-bound protocol
/// to act as `AnyObject` in a `AnyObject` generic constraint (i.e. `WeakList`)
@objc public protocol PreferencesObserver: AnyObject {
  /// A preference value was changed for some given preference key
  func preferencesDidChange(for key: String)
}

extension Preferences {

  /// An entry in the `Preferences`
  ///
  /// `ValueType` defines the type of value that will stored in the UserDefaults object
  public class Option<ValueType: UserDefaultsEncodable & Equatable>: ObservableObject {
    /// The list of observers for this option
    private let observers = WeakList<PreferencesObserver>()
    /// The UserDefaults container that you wish to save to
    public let container: UserDefaults
    /// The current value of this preference
    ///
    /// Upon setting this value, UserDefaults will be updated and any observers will be called
    @Published public var value: ValueType {
      didSet {
        if value == oldValue { return }

        // Check if `ValueType` is something that can be nil
        if value is ExpressibleByNilLiteral {
          // We have to use a weird workaround to determine if it can be placed in the UserDefaults.
          // `nil` (NSNull when its bridged to ObjC) can be placed in a dictionary, but not in UserDefaults.
          let dictionary = NSMutableDictionary(object: value, forKey: self.key as NSString)
          // If the value we pull out of the dictionary is NSNull, we know its nil and should remove it
          // from the UserDefaults rather than attempt to set it
          if let value = dictionary[self.key], value is NSNull {
            container.removeObject(forKey: self.key)
          } else {
            container.set(value, forKey: self.key)
          }
        } else { 
          container.set(value, forKey: self.key)
        }
        container.synchronize()

        let key = self.key
        observers.forEach {
          $0.preferencesDidChange(for: key)
        }
      }
    }
    /// Adds `object` as an observer for this Option.
    public func observe(from object: PreferencesObserver) {
      observers.insert(object)
    }
    /// The key used for getting/setting the value in `UserDefaults`
    public let key: String
    /// The default value of this preference
    public let defaultValue: ValueType
    /// Reset's the preference to its original default value
    public func reset() {
      value = defaultValue
    }

    /// Creates a preference
    public init(key: String, default: ValueType, container: UserDefaults = Preferences.defaultContainer) {
      self.key = key
      self.container = container
      self.defaultValue = `default`
      value = (container.value(forKey: key) as? ValueType) ?? `default`
    }
  }
}

extension Optional: UserDefaultsEncodable where Wrapped: UserDefaultsEncodable {}
extension Bool: UserDefaultsEncodable {}
extension Int: UserDefaultsEncodable {}
extension UInt: UserDefaultsEncodable {}
extension Float: UserDefaultsEncodable {}
extension Double: UserDefaultsEncodable {}
extension String: UserDefaultsEncodable {}
extension URL: UserDefaultsEncodable {}
extension Data: UserDefaultsEncodable {}
extension Date: UserDefaultsEncodable {}
extension Array: UserDefaultsEncodable where Element: UserDefaultsEncodable {}
extension Dictionary: UserDefaultsEncodable where Key: StringProtocol, Value: UserDefaultsEncodable {}
