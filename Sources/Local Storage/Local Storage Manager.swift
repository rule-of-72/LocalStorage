//
//  Local Storage Manager.swift
//

import UIKit
import UniformTypeIdentifiers

fileprivate let byteOrderMark = "\u{FEFF}"


public class LocalStorageManager {

    // MARK: Type definitions

    public typealias Result = Swift.Result<Void, Error>
    public typealias Completion = (Result) -> Void

    public typealias DataResult = Swift.Result<Data, Error>
    public typealias DataCompletion = (DataResult) -> Void

    public typealias StringResult = Swift.Result<String, Error>
    public typealias StringCompletion = (StringResult) -> Void

    // MARK: Public properties
    
    public let filename: String

    // MARK: Initializers

    public init(baseFilename: String, uniqueSuffix: String? = nil, type: UTType, temporary: Bool = false) {
        assert(type != .text, "Don't use .text, use .plainText instead.")
        
        self.filenamePrefix = baseFilename
        if let uniqueSuffix = uniqueSuffix {
            self.filename = [ baseFilename, uniqueSuffix ].joined(separator: " ")
        } else {
            self.filename = baseFilename
        }

        self.type = type

        if temporary {
            storageDirectory = fileManager.temporaryDirectory
        } else {
            storageDirectory = try! fileManager.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        }
    }

    // MARK: Public methods

    public func readLocalFile(completion: @escaping DataCompletion) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = DataResult { try self.readLocalFile() }
            originalQueue.addOperation { completion(result) }
        }
    }

    public func readLocalFile(encoding: String.Encoding = .utf8, completion: @escaping StringCompletion) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = StringResult { try self.readLocalFile(encoding: encoding) }
            originalQueue.addOperation { completion(result) }
        }
    }

    public func writeLocalFile(_ data: Data, completion: @escaping Completion) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = Result { try self.writeLocalFile(data) }
            originalQueue.addOperation { completion(result) }
        }
    }

    public func writeLocalFile(_ string: String, encoding: String.Encoding = .utf8, completion: @escaping Completion) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let data = string.data(using: encoding)!
            let result = Result { try self.writeLocalFile(data) }
            originalQueue.addOperation { completion(result) }
        }
    }

    public func appendLocalFile(_ additionalString: String, headerIfNewFile headerString: String? = nil, encoding: String.Encoding = .utf8, completion: Completion?) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = Result {
                let exists = self.fileManager.fileExists(atPath: self.localFileURL.path)
                let additionalData = additionalString.data(using: encoding)!

                switch (exists, headerString) {
                    case (false, let headerString?):
                        let headerData = headerString.data(using: encoding)!
                        try self.writeLocalFile(headerData)
                        try self.appendLocalFile(additionalData)

                    case (false, nil):
                        try self.writeLocalFile(additionalData)

                    case (true, _):
                        try self.appendLocalFile(additionalData)
                }
            }

            if let completion = completion {
                originalQueue.addOperation { completion(result) }
            }
        }
    }

    public func exportLocalFile(toDirectory directoryURL: URL, completion: Completion? = nil) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = Result {
                try self.exportLocalFile(toDirectory: directoryURL)
            }

            if let completion = completion {
                originalQueue.addOperation { completion(result) }
            }
        }
    }

    public func deleteLocalFiles(completion: Completion? = nil) {
        let originalQueue = OperationQueue.current!

        workerQueue.addOperation {
            let result = Result { try self.cleanLocalStorage() }
            if let completion = completion {
                originalQueue.addOperation { completion(result) }
            }
        }
    }

    public func hasLocalFiles() -> Bool {
        if let allFiles = try? self.filesInLocalStorage() {
            return !allFiles.isEmpty
        } else {
            return false
        }
    }

    public func localFileLastSaved() -> Date? {
        let path = localFileURL.path
        guard fileManager.isReadableFile(atPath: path) else { return nil }
        guard let attributes = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        guard let date = attributes[.creationDate] as? Date else { return nil }

        return date
    }

    // MARK: Private methods

    private func readLocalFile() throws -> Data {
        assert(OperationQueue.current! === workerQueue)

        return try Data(contentsOf: localFileURL)
    }

    private func readLocalFile(encoding: String.Encoding) throws -> String {
        assert(OperationQueue.current! === workerQueue)

        var contents = try String(contentsOf: localFileURL, encoding: encoding)
        if contents.hasPrefix(byteOrderMark) {
            contents.removeFirst()
        }

        return contents
    }

    private func writeLocalFile(_ data: Data) throws {
        assert(OperationQueue.current! === workerQueue)

        try data.write(to: localFileURL, options: .atomic)
    }

    private func appendLocalFile(_ data: Data) throws {
        assert(OperationQueue.current! === workerQueue)

        // Will fail if file doesn't exist. Caller's job to check!
        let fileHandle = try FileHandle(forWritingTo: localFileURL)
        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: data)
        try fileHandle.close()
    }

    private func exportLocalFile(toDirectory directoryURL: URL) throws {
        assert(OperationQueue.current! === workerQueue)

        let uniqueFilename = self.localFileURL.lastPathComponent
        let destinationFileURL = directoryURL.appendingPathComponent(uniqueFilename, isDirectory: false)

        guard directoryURL.startAccessingSecurityScopedResource() else {
            throw CocoaError(.fileWriteNoPermission, url: directoryURL)
        }

        defer {
            directoryURL.stopAccessingSecurityScopedResource()
        }

        var coordinatorError: NSError? = nil
        var copyError: Error? = nil
        NSFileCoordinator().coordinate(writingItemAt: destinationFileURL, options: [.forReplacing], error: &coordinatorError) { url in
            do {
                try? fileManager.removeItem(at: destinationFileURL)
                try fileManager.copyItem(at: localFileURL, to: destinationFileURL)
            } catch (let error) {
                copyError = error
            }
        }

        if let coordinatorError = coordinatorError {
            print("Coordinator error: \(coordinatorError)")
            throw coordinatorError
        } else if let copyError = copyError {
            print("Copy error: \(copyError)")
            throw copyError
        }
    }

    private func cleanLocalStorage() throws {
        assert(OperationQueue.current! === workerQueue)

        for file in try filesInLocalStorage() {
            try fileManager.removeItem(at: file)
        }
    }

    private func moveToLocalStorage(url sourceURL: URL) throws {
        // Don't assert that we're on our worker queue. We might be on the URL download task's delegate queue.

        let newLocalFileURL = try fileManager.replaceItemAt(localFileURL, withItemAt: sourceURL, backupItemName: nil, options: .usingNewMetadataOnly)
        localFileURL = newLocalFileURL ?? localFileURL
    }

    private func filesInLocalStorage() throws -> [URL] {
        var localFiles: [URL] = []

        do {
            let allFiles = try fileManager.contentsOfDirectory(at: storageDirectory, includingPropertiesForKeys: [])
            localFiles = allFiles.filter {
                $0.lastPathComponent.starts(with: filenamePrefix) &&
                $0.pathExtension == type.preferredFilenameExtension
            }
        }

        return localFiles
    }

    // MARK: Private properties

    private lazy var workerQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "\(String(describing: Self.self)) worker queue"
        return queue
    }()

    private lazy var localFileURL: URL = storageDirectory.appendingPathComponent(filename, conformingTo: type)

    private let filenamePrefix: String
    private let type: UTType
    private let storageDirectory: URL
    private let fileManager = FileManager.default

}


// MARK: - Web downloads

public extension LocalStorageManager {

    struct HTTPError: LocalizedError {
        public let statusCode: Int

        fileprivate init(_ statusCode: Int) {
            self.statusCode = statusCode
        }

        public var errorDescription: String? {
            "\(statusCode): " + HTTPURLResponse.localizedString(forStatusCode: statusCode)
        }
    }

    func downloadFile(url: URL, completion: @escaping Completion) {
        let originalQueue = OperationQueue.current!

        func reportResult(_ result: Result) {
            originalQueue.addOperation {
                completion(result)
            }
        }

        guard url.scheme == "https" else {
            print("Error downloading file from URL \(url):\n" +
                  "URL does not use https:// scheme")
            reportResult(.failure(CocoaError(.fileReadUnsupportedScheme, url: url)))
            return
        }

        let downloadTask = URLSession.shared.downloadTask(with: url) { (tempFileURL, response, error) in
            let result: Result

            switch (tempFileURL, response, error) {
                case (let tempFileURL?, let response as HTTPURLResponse, nil)
                    where (200 ... 299).contains(response.statusCode):
                    result = Result {
                        try self.moveToLocalStorage(url: tempFileURL)
                    }

                case (_, _, let error?):
                    print("Error downloading file from URL \(url):\n" +
                          "\(error)")
                    result = .failure(error)

                case (_, let response as HTTPURLResponse, _):
                    let error = HTTPError(response.statusCode)
                    print("Error downloading file from URL \(url):\n" +
                          "HTTP status \(error)")
                    result = .failure(error)

                default:
                    print("Unexpected/Unknown response downloading file from URL \(url)")
                    result = .failure(CocoaError(.fileReadUnknown, url: url))
            }

            reportResult(result)
        }

        downloadTask.resume()
    }

}


// MARK: - User Interface

public extension LocalStorageManager {

    func importFile(hostingViewController vc: UIViewController, completion: Completion?) {
        assert(OperationQueue.current! === OperationQueue.main, "Must call on main queue")

        func reportResult(_ result: Result) {
            if let completion = completion {
                OperationQueue.main.addOperation {
                    completion(result)
                }
            }
        }

        DocumentPickerWithStrongDelegate.showOpenDocumentPicker(forTypes: [type], hostingViewController: vc) { pickedURL in
            guard let pickedURL = pickedURL else {
                reportResult(.failure(CocoaError(.userCancelled)))
                return
            }

            self.workerQueue.addOperation {
                let result = Result {
                    try self.cleanLocalStorage()
                    try self.moveToLocalStorage(url: pickedURL)
                }

                reportResult(result)
            }
        }
    }

    func exportFiles(hostingViewController vc: UIViewController, completion: Completion?) {
        assert(OperationQueue.current! === OperationQueue.main, "Must call on main queue")

        func reportResult(_ result: Result) {
            if let completion = completion {
                OperationQueue.main.addOperation {
                    completion(result)
                }
            }
        }

        let allFiles: [URL]
        do {
            allFiles = try self.filesInLocalStorage()
        } catch {
            reportResult(.failure(error))
            return
        }

        guard allFiles.count > 0 else {
            reportResult(.failure(CocoaError(.fileNoSuchFile)))
            return
        }

        DocumentPickerWithStrongDelegate.showExportDocumentPicker(forFiles: allFiles, hostingViewController: vc) { exportedURL in
            guard exportedURL != nil else {
                reportResult(.failure(CocoaError(.userCancelled)))
                return
            }

            reportResult(.success(()))
        }
    }

}


// MARK: - Custom errors

fileprivate extension CocoaError {

    init(_ code: CocoaError.Code, url: URL) {
        self.init(code, userInfo: [NSURLErrorKey : url] )
    }

}
