// swiftlint:disable file_length
import AppKit.NSRunningApplication
import Defaults
import Foundation
import Logging
import Observation
import Sauce
import SwiftData

@Observable
class History: ItemsContainer { // swiftlint:disable:this type_body_length
  static let shared = History()
  let logger = Logger(label: "local.multiram.MultiRam")

  var items: [HistoryItemDecorator] = []
  var pasteStack: PasteStack?
  var storageError: String?

  @ObservationIgnored private let suppliedContext: ModelContext?
  // Runs after the history is cleared, for example to remove exported copies of its images.
  @ObservationIgnored var onClear: (() -> Void)?
  @ObservationIgnored private let saveChanges: (ModelContext) throws -> Void

  @MainActor
  private var context: ModelContext { suppliedContext ?? Storage.shared.context }

  var pinnedItems: [HistoryItemDecorator] { items.filter(\.isPinned) }
  var unpinnedItems: [HistoryItemDecorator] { items.filter(\.isUnpinned) }

  // Shows only text, images or files; the popup resets it to all when it closes.
  var filter: HistoryFilter = .all {
    didSet {
      guard filter != oldValue else { return }
      refreshItems()
      AppState.shared.navigator.select(item: unpinnedItems.first ?? pinnedItems.first)
      AppState.shared.popup.needsResize = true
    }
  }

  var searchQuery: String = "" {
    didSet {
      guard searchQuery != oldValue else { return }
      throttler.throttle { [self] in
        refreshItems()

        if searchQuery.isEmpty {
          AppState.shared.navigator.select(item: unpinnedItems.first)
        } else {
          AppState.shared.navigator.highlightFirst()
        }

        AppState.shared.popup.needsResize = true
      }
    }
  }

  var pressedShortcutItem: HistoryItemDecorator? {
    guard let event = NSApp.currentEvent else { return nil }
    return item(forShortcut: event)
  }

  func item(forShortcut event: NSEvent) -> HistoryItemDecorator? {
    let modifierFlags = event.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting(.capsLock)

    guard HistoryItemAction(modifierFlags) != .unknown else {
      return nil
    }

    let key = Sauce.shared.key(for: Int(event.keyCode))
    return pinnedItems.first { $0.shortcuts.contains(where: { $0.key == key }) }
  }

  private let search = Search()
  private let sorter = Sorter()
  private let throttler = Throttler(minimumDelay: 0.2)

  @ObservationIgnored
  private var sessionLog: [Int: HistoryItem] = [:]

  // The distinction between `all` and `items` is the following:
  // - `all` stores all history items, even the ones that are currently hidden by a search
  // - `items` stores only visible history items, updated during a search
  @ObservationIgnored
  var all: [HistoryItemDecorator] = []

  init(
    context: ModelContext? = nil,
    observeDefaults: Bool = true,
    saveChanges: @escaping (ModelContext) throws -> Void = { try $0.save() }
  ) {
    self.suppliedContext = context
    self.saveChanges = saveChanges
    guard observeDefaults else { return }
    Task { @MainActor in
      for await _ in Defaults.updates(.sortBy, initial: false) {
        await reload()
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.pinTo, initial: false) {
        await reload()
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.showSpecialSymbols, initial: false) {
        for item in all {
          updateTitle(item: item, title: item.item.generateTitle())
        }
      }
    }

    Task { @MainActor in
      for await _ in Defaults.updates(.imageMaxHeight, initial: false) {
        for item in all {
          item.refreshImages()
        }
      }
    }
  }

  @MainActor
  func load() async throws {
    let descriptor = FetchDescriptor<HistoryItem>()
    let results = try context.fetch(descriptor)
    all = sorter.sort(results).map { HistoryItemDecorator($0) }
    items = all

    limitHistorySize(to: max(1, Defaults[.size]))
    removeExpired()
    refreshItems()
    // Ensure that panel size is proper *after* loading all items.
    Task {
      AppState.shared.popup.needsResize = true
    }
  }

  @MainActor
  func reload() async {
    do {
      try await load()
    } catch {
      reportStorageError(error)
    }
  }

  @MainActor
  private func limitHistorySize(to maxSize: Int) {
    let excess = Array(all.filter(\.isUnpinned).dropFirst(max(0, maxSize)))
    guard !excess.isEmpty else { return }
    guard persist({ excess.forEach { context.delete($0.item) } }) else { return }
    excess.forEach { removeFromMemory($0) }
    refreshItems()
  }

  // Deletes unpinned items last copied before the retention period.
  @MainActor
  func removeExpired(retention: HistoryRetention = Defaults[.historyRetention], now: Date = .now) {
    guard let cutoff = retention.cutoff(now: now) else { return }
    let expired = all.filter { $0.isUnpinned && !$0.item.isDeleted && $0.item.lastCopiedAt < cutoff }
    guard !expired.isEmpty else { return }
    guard persist({ expired.forEach { context.delete($0.item) } }) else { return }
    expired.forEach { removeFromMemory($0) }
    refreshItems()
    AppState.shared.popup.needsResize = true
  }

  @MainActor
  func insertIntoStorage(_ item: HistoryItem) throws {
    // macOS 14 requires insertion before accessing model relationships.
    context.insert(item)
  }

  @discardableResult
  @MainActor
  func add(_ item: HistoryItem) -> HistoryItemDecorator? {
    do {
      let existing = try findSimilarItem(item)
      let savedItem: HistoryItem
      if let existing {
        if isModified(item) != nil {
          let contents = item.contents.map { HistoryItemContent(type: $0.type, value: $0.value) }
          existing.contents.forEach { context.delete($0) }
          existing.contents = contents
          existing.title = item.title
        }
        existing.lastCopiedAt = item.lastCopiedAt
        existing.numberOfCopies += item.numberOfCopies
        savedItem = existing
        // Keep the original model and decorator so pins, selection and relationships remain valid.
        if item.modelContext != nil {
          context.delete(item)
        }
      } else {
        context.insert(item)
        savedItem = item
      }

      let candidates = all.map(\.item).filter { $0 != savedItem && $0.pin == nil }
      let remainingCapacity = max(1, Defaults[.size]) - (savedItem.pin == nil ? 1 : 0)
      let excess = Array(sorter.sort(candidates).dropFirst(remainingCapacity))
      excess.forEach { context.delete($0) }
      context.processPendingChanges()
      try saveChanges(context)

      let decorator = all.first { $0.item == savedItem } ?? HistoryItemDecorator(savedItem)
      if existing != nil {
        decorator.title = savedItem.title
        decorator.refreshContentFlags()
        decorator.cleanupImages()
        decorator.ensureThumbnailImage()
      }
      let removed = all.filter { excess.contains($0.item) }
      removed.forEach { removeFromMemory($0) }
      if !all.contains(decorator) {
        all.append(decorator)
      }
      // Keep pinned items in their original order when copying them again.
      let pinned = all.filter(\.isPinned)
      let unpinned = sorter.sort(all.filter(\.isUnpinned).map(\.item))
      let unpinnedDecorators = unpinned.compactMap { model in all.first { $0.item == model } }
      all = Defaults[.pinTo] == .bottom ? unpinnedDecorators + pinned : pinned + unpinnedDecorators
      sessionLog.removeValues { $0 == savedItem }
      sessionLog[Clipboard.shared.changeCount] = savedItem
      refreshItems()
      AppState.shared.popup.needsResize = true
      if existing == nil {
        Notifier.notify(body: savedItem.title, sound: .write)
      }
      return decorator
    } catch {
      context.rollback()
      reportStorageError(error)
      return nil
    }
  }

  @MainActor
  private func persist(_ changes: () throws -> Void) -> Bool {
    do {
      try changes()
      context.processPendingChanges()
      try saveChanges(context)
      return true
    } catch {
      context.rollback()
      reportStorageError(error)
      return false
    }
  }

  @MainActor
  private func reportStorageError(_ error: Error) {
    let error = error as NSError
    logger.error("History storage operation failed", metadata: [
      "domain": "\(error.domain)", "code": "\(error.code)"
    ])
    storageError = NSLocalizedString("HistoryStorageError", comment: "History could not be saved")
  }

  @discardableResult
  @MainActor
  func clear() -> Bool {
    clearHistory(includingPinned: false)
  }

  @discardableResult
  @MainActor
  func clearAll() -> Bool {
    clearHistory(includingPinned: true)
  }

  @MainActor
  private func clearHistory(includingPinned: Bool) -> Bool {
    let removed = all.filter { includingPinned || $0.isUnpinned }
    guard persist({
      let stored = try context.fetch(FetchDescriptor<HistoryItem>())
      for item in stored where includingPinned || item.pin == nil {
        context.delete(item)
      }
    }) else { return false }

    removed.forEach { removeFromMemory($0) }
    onClear?()
    interruptPasteStack()
    items = all.filter { filter.includes($0.kind) }
    searchQuery = ""
    AppState.shared.navigator.select(item: items.first)
    Clipboard.shared.clear()
    AppState.shared.popup.close()
    AppState.shared.popup.needsResize = true
    return true
  }

  @discardableResult
  @MainActor
  func delete(_ item: HistoryItemDecorator?) -> Bool {
    guard let item else { return false }
    guard persist({ context.delete(item.item) }) else { return false }
    removeFromMemory(item)
    AppState.shared.popup.needsResize = true
    return true
  }

  @MainActor
  private func removeFromMemory(_ item: HistoryItemDecorator) {
    if AppState.shared.popup.detailItem === item {
      AppState.shared.popup.closeDetail()
    }
    cleanup(item)
    all.removeAll { $0 == item }
    items.removeAll { $0 == item }
    sessionLog.removeValues { $0 == item.item }
  }

  @MainActor
  private func cleanup(_ item: HistoryItemDecorator) {
    item.cleanupImages()
  }

  private func currentModifierFlags() -> NSEvent.ModifierFlags {
    return NSApp.currentEvent?.modifierFlags
      .intersection(.deviceIndependentFlagsMask)
      .subtracting([.capsLock, .numericPad, .function]) ?? []
  }

  @MainActor
  func select(_ item: HistoryItemDecorator?) {
    guard let item else {
      return
    }

    let modifierFlags = currentModifierFlags()

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      if Defaults[.pasteByDefault] {
        Clipboard.shared.paste()
      }
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
        Clipboard.shared.paste()
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  // Text of the chosen items in the order they were chosen, one per line; images and files are skipped.
  static func mergedText(of items: [HistoryItemDecorator]) -> String? {
    let texts = items
      .filter { $0.kind == .text && !$0.item.isDeleted }
      .map(\.item.previewableText)
      .filter { !$0.isEmpty }
    return texts.isEmpty ? nil : texts.joined(separator: "\n")
  }

  @MainActor
  func pasteMerged(_ items: [HistoryItemDecorator]) {
    guard let text = Self.mergedText(of: items) else { return }
    let modifierFlags = currentModifierFlags()
    let action = modifierFlags.isEmpty ? nil : HistoryItemAction(modifierFlags)
    guard action != .unknown else { return }

    AppState.shared.popup.close()
    Clipboard.shared.copy(text)
    if action == .paste || action == .pasteWithoutFormatting || (action == nil && Defaults[.pasteByDefault]) {
      Clipboard.shared.paste()
    }

    Task {
      searchQuery = ""
    }
  }

  @MainActor
  func startPasteStack(selection: inout Selection<HistoryItemDecorator>) {
    guard AppState.shared.multiSelectionEnabled else { return }
    guard let item = selection.first else { return }
    PasteStack.initializeIfNeeded()

    let modifierFlags = currentModifierFlags()

    let stack = PasteStack(items: selection.items, modifierFlags: modifierFlags)
    pasteStack = stack

    logger.info("Initialising PasteStack with \(stack.items.count) items")
    logger.info("Copying item from PasteStack")

    if modifierFlags.isEmpty {
      AppState.shared.popup.close()
      Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
    } else {
      switch HistoryItemAction(modifierFlags) {
      case .copy:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .paste:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item)
      case .pasteWithoutFormatting:
        AppState.shared.popup.close()
        Clipboard.shared.copy(item.item, removeFormatting: true)
        Clipboard.shared.paste()
      case .unknown:
        return
      }
    }

    Task {
      searchQuery = ""
    }
  }

  func handlePasteStack() {
    guard let stack = pasteStack else {
      return
    }

    guard !stack.items.isEmpty else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("PasteStack item pasted")

    stack.items.removeFirst()

    guard let item = stack.items.first else {
      pasteStack = nil
      logger.info("PasteStack is empty")
      return
    }

    logger.info("Copying item from PasteStack. \(stack.items.count) items remaining in stack.")

    Task {
      if stack.modifierFlags.isEmpty {
        await Clipboard.shared.copy(item.item, removeFormatting: Defaults[.removeFormattingByDefault])
      } else {
        switch HistoryItemAction(stack.modifierFlags) {
        case .copy:
          await Clipboard.shared.copy(item.item)
        case .paste:
          await Clipboard.shared.copy(item.item)
        case .pasteWithoutFormatting:
          await Clipboard.shared.copy(item.item, removeFormatting: true)
        case .unknown:
          return
        }
      }
    }
  }

  func interruptPasteStack() {
    guard pasteStack != nil else {
      return
    }
    logger.info("Interrupting PasteStack")
    pasteStack = nil
  }

  @MainActor
  func togglePin(_ item: HistoryItemDecorator?) {
    guard let item else { return }

    guard persist({ item.togglePin() }) else { return }

    let sortedItems = sorter.sort(all.map(\.item))
    if let currentIndex = all.firstIndex(of: item),
       let newIndex = sortedItems.firstIndex(of: item.item) {
      all.remove(at: currentIndex)
      all.insert(item, at: newIndex)
    }

    items = all

    searchQuery = ""
    if item.isUnpinned {
      AppState.shared.navigator.scrollTarget = item.id
    }
  }

  @MainActor
  private func findSimilarItem(_ item: HistoryItem) throws -> HistoryItem? {
    let stored = try context.fetch(FetchDescriptor<HistoryItem>())
    return stored.first { $0 != item && $0.supersedes(item) } ?? isModified(item)
  }

  private func isModified(_ item: HistoryItem) -> HistoryItem? {
    if let modified = item.modified, sessionLog.keys.contains(modified) {
      return sessionLog[modified]
    }

    return nil
  }

  private func refreshItems() {
    let candidates = filter == .all ? all : all.filter { filter.includes($0.kind) }
    updateItems(search.search(string: searchQuery, within: candidates))
  }

  private func updateItems(_ newItems: [Search.SearchResult]) {
    items = newItems.map { result in
      let item = result.object
      item.highlight(searchQuery, result.ranges)

      return item
    }
  }

  @MainActor
  private func updateTitle(item: HistoryItemDecorator, title: String) {
    item.title = title
    item.item.title = title
  }
}
