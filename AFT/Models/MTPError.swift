import Foundation

enum MTPError: LocalizedError, Equatable {
    case notConnected
    case connectFailed
    case communicationFailed
    case storageLocked
    case copyFailed(String)
    case createFolderFailed
    case deleteFailed(String)
    case renameFailed(String)
    case underlying(String)

    var errorDescription: String? {
        switch self {
        case .notConnected, .connectFailed: return "Could not connect to device"
        case .communicationFailed: return "Could not communicate with device"
        case .storageLocked: return "Can't access device storage"
        case .copyFailed(let n): return "Could not copy file \"\(n)\""
        case .createFolderFailed: return "Could not create folder"
        case .deleteFailed(let n): return "Could not delete file or folder named \"\(n)\""
        case .renameFailed(let n): return "Could not rename \"\(n)\""
        case .underlying(let m): return m
        }
    }

    init(_ error: Error) { self = .underlying(error.localizedDescription) }
}
