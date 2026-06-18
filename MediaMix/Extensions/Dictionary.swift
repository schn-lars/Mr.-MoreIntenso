import Foundation

/**
 https://stackoverflow.com/questions/26728477/how-can-i-combine-two-dictionary-instances-in-swift
 */
extension Dictionary {
    mutating func merge(dict: [Key: Value]) {
        for (k, v) in dict {
            updateValue(v, forKey: k)
        }
    }
}
