import Foundation

public enum ProjectFramework: String, Codable, Sendable {
    case reactNative = "react-native"
    case flutter
    case nativeIOS = "native-ios"
    case nativeAndroid = "native-android"

    public var displayName: String {
        switch self {
        case .reactNative: "React Native"
        case .flutter: "Flutter"
        case .nativeIOS: "native iOS"
        case .nativeAndroid: "native Android"
        }
    }
}
