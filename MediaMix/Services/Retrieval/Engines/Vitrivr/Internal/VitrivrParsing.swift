//
//  VitrivrParsing.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import AnyCodable
import Foundation

enum VitrivrParsing {
    static func toDoubleVector(_ any: Any?) -> [Double]? {
        guard let any else { return nil }
        if let d = any as? [Double] { return d }
        if let f = any as? [Float] { return f.map(Double.init) }
        if let n = any as? [NSNumber] { return n.map { $0.doubleValue } }
        if let a = any as? [Any] {
            return a.compactMap {
                if let d = $0 as? Double { return d }
                if let f = $0 as? Float { return Double(f) }
                if let n = $0 as? NSNumber { return n.doubleValue }
                return nil
            }
        }
        return nil
    }

    static func extractInt64(_ any: AnyCodable?) -> Int64? {
        guard let v = any?.value else { return nil }
        if let i = v as? Int64 { return i }
        if let i = v as? Int { return Int64(i) }
        if let d = v as? Double { return Int64(d) }
        if let s = v as? String, let i = Int64(s) { return i }
        return nil
    }

    static func extractVideoId(from r: VitrivrRetrievable) -> String? {
        if let partOf = r.relationship?["partOf"],
           let path = partOf.descriptors?["file.path"]?.value as? String
        {
            return (path as NSString).lastPathComponent
                .replacingOccurrences(of: ".mp4", with: "")
        }
        return nil
    }
}
