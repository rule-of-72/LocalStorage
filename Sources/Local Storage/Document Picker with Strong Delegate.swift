//
//  Document Picker with Strong Delegate.swift
//

import UIKit
import UniformTypeIdentifiers

public class DocumentPickerWithStrongDelegate: UIDocumentPickerViewController {

    public typealias Completion = (URL?) -> Void

    public static func showOpenDocumentPicker(forTypes types: [UTType], hostingViewController vc: UIViewController, completion: @escaping Completion) {
        assert(!types.contains(.folder), "Use showFolderPicker for folders.")
        let documentPicker = DocumentPickerWithStrongDelegate(forOpeningContentTypes: types, asCopy: true)
        documentPicker.show(hostingViewController: vc, completion: completion)
    }

    public static func showFolderPicker(hostingViewController vc: UIViewController, completion: @escaping Completion) {
        let documentPicker = DocumentPickerWithStrongDelegate(forOpeningContentTypes: [.folder], asCopy: false)
        documentPicker.show(hostingViewController: vc, completion: completion)
    }

    public static func showExportDocumentPicker(forFiles files: [URL], hostingViewController vc: UIViewController, completion: @escaping Completion) {
        assert(!files.isEmpty)
        let documentPicker = DocumentPickerWithStrongDelegate(forExporting: files, asCopy: true)
        documentPicker.show(hostingViewController: vc, completion: completion)
    }

    public override weak var delegate: (UIDocumentPickerDelegate)? {
        didSet {
            strongDelegate = delegate
        }
    }

    private func show(hostingViewController vc: UIViewController, completion: @escaping Completion) {
        shouldShowFileExtensions = true

        let delegate = DocumentPickerDelegate(completion: completion)
        self.delegate = delegate

        vc.present(self, animated: true, completion: nil)
    }

    private var strongDelegate: (UIDocumentPickerDelegate)?

}


fileprivate class DocumentPickerDelegate: NSObject, UIDocumentPickerDelegate {

    public init(completion: @escaping DocumentPickerWithStrongDelegate.Completion) {
        self.completion = completion

        super.init()
    }

    public func documentPicker(_ picker: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        completion(urls.last)
    }

    public func documentPickerWasCancelled(_ picker: UIDocumentPickerViewController) {
        completion(nil)
    }

    private let completion: DocumentPickerWithStrongDelegate.Completion

}
