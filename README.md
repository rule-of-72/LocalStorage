# Local Storage

Classes for managing files in the local app sandbox.

## Local Storage Manager

The `LocalStorageManager` class manages a single file or a group of related files (based on a common filename prefix) stored in the app sandbox.

Supported operations include:
- Read
- Write
- Append
    - Including support for writing a header, if the file needs to be created.
- Delete
- Test for presence
- Get creation date

### Why?

Apple already provides support classes for managing “documents.” But not all local files are “documents,” meaning: a user-owned file that the user views or edits with your app.

For example, your app may keep a configuration file called `config.json` in one of its sandbox directories. You may need to know whether the file is present and, if so, how old it is. You certainly need to read it and to write it, maybe to delete it. `LocalStorageManager` takes care of this boilerplate file management.

**Other Examples:**
- Log files
- Temp files
- Generated files
	- For example: PDF files that the app never reopens after they’re exported.
- Downloaded files
	- For example: configuration files from your server that the app caches locally.
- A user file that the app copies to its sandbox for repeated use, even if the original file gets moved or deleted.

## Document Picker with Strong Delegate

The `DocumentPickerWithStrongDelegate` class subclasses the standard Apple `UIDocumentPickerViewController` and supports two additional patterns for handling results:
- Factor your delegate code into a separate helper class with its own state.
    - The `.delegate` property retains a *strong* reference to your delegate object, so you don’t need to keep your own reference to it. Create it, set it, and forget it.
    - The delegate object gets cleaned up automatically after the `UIDocumentPickerViewController` dismisses.
- Use a closure instead of a delegate.
    - Capture relevant context/state in the closure.
    - Write the code to handle results in the same place as the code that creates the document picker.

### Why?

The traditional pattern for using a view controller with a weak delegate, including `UIDocumentPickerViewController`, involves:
- Implementing the delegate methods as an extension of your primary view controller.
- Adding member variables to your primary view controller to hold any necessary context/state while the document picker is presented.
- Setting your primary view controller as the delegate of the document picker.
- Cleaning up the member variables after the document picker gets dismissed.

This burdens your primary view controller with extra responsibilities as well as extra member variables that are only infrequently relevant. Isolating that logic and state into a closure or a separate object relieves this burden.
