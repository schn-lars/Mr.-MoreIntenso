//
//  AppModel.swift
//  MediaMix
//
//  Created by Rahel Arnold
//

import SwiftUI

/// `AppModel` is responsible for maintaining the global application state,
/// including managing the immersive space used for 3D experiences.
@MainActor
@Observable
class AppModel {
    /// The unique identifier for the immersive space.
    /// This ID is used when opening or dismissing the immersive mode.
    let immersiveSpaceID = "ImmersiveSpace"

    /// Represents the current state of the immersive space.
    enum ImmersiveSpaceState {
        /// The immersive space is not active.
        case closed
        /// The immersive space is in the process of opening or closing.
        case inTransition
        /// The immersive space is currently active and open.
        case open
    }

    /// Tracks the current state of the immersive space.
    /// Default state is `.closed` until it is explicitly opened.
    var immersiveSpaceState = ImmersiveSpaceState.open
    
    enum AppMode: String {
        /// The application is doing inference
        case intenso
        
        /// The application is set to use MediaMix
        case mediamix
        
        var displayName: String {
            switch self {
            case .intenso:   return "Intenso"
            case .mediamix:  return "MediaMix"
            }
        }
    }
    
    /// Tracks the current state of the application mode
    /// Default state is `.intenso`, meaning inference is the main usage
    var appMode = AppMode.intenso
    
    /// Tracks the currently logged in user
    var username: String? = nil
}
