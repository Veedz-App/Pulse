// The MIT License (MIT)
//
// Copyright (c) 2020–2023 Alexander Grebenyuk (github.com/kean).

#if os(macOS)

import SwiftUI
import CoreData
import Pulse
import Combine

struct ConsoleTextItemViewModel {
    var range = NSRange(location: NSNotFound, length: 0)
}

final class ConsoleTextViewModel: ObservableObject {
    var text = RichTextViewModel()
    var options: TextRenderer.Options = .init()

    var isViewVisible = false {
        didSet {
            if isViewVisible {
                refresh()
            }
        }
    }

    private let list: ConsoleListViewModel
    private let router: ConsoleRouter
    private var content: NetworkContent = []
    private var entities: [NSManagedObject] { list.entities }
    private var items: [ConsoleTextItemViewModel] = []
    private var cache: [NSManagedObjectID: NSAttributedString] = [:]
    private var cancellables: [AnyCancellable] = []

    init(list: ConsoleListViewModel, router: ConsoleRouter) {
        self.list = list
        self.router = router

        self.text.onLinkTapped = { [unowned self] in onLinkTapped($0) }
        self.text.isLinkDetectionEnabled = false

        list.updates.sink { [weak self] in
            guard let self = self, self.isViewVisible else { return }
            switch $0 {
            case .reload: self.refresh()
            case .diff(let diff): self.apply(diff)
            }
        }.store(in: &cancellables)
    }

    private func apply(_ diff: CollectionDifference<NSManagedObjectID>) {
        let renderer = TextRenderer(options: options)
        text.performUpdates {
            for change in diff {
                switch change {
                case let .insert(offset, objectID, _):
                    cache[objectID] = nil
                    insertEntity(at: offset, storage: $0, using: renderer)
                case let .remove(offset, objectID, _):
                    cache[objectID] = nil
                    removeEntity(at: offset, storage: $0)
                }
            }
        }
    }

    private func insertEntity(at offset: Int, storage: NSTextStorage, using renderer: TextRenderer) {
        let entity = entities[offset]
        var viewModel = ConsoleTextItemViewModel()

        let string = render(entity, using: renderer)

        let insertionStringIndex = offset > 0 ? items[offset - 1].range.upperBound : 0
        viewModel.range = NSRange(location: insertionStringIndex, length: string.length)

        storage.insert(string, at: insertionStringIndex)
        items.insert(viewModel, at: offset)

        for index in (offset + 1)..<items.endIndex {
            items[index].range.location += viewModel.range.length
        }
    }

    private func removeEntity(at offset: Int, storage: NSTextStorage) {
        let viewModel = items[offset]
        items.remove(at: offset)
        storage.deleteCharacters(in: viewModel.range)

        for index in offset..<items.endIndex {
            items[index].range.location -= viewModel.range.length
        }
    }

    private func refresh() {
        let renderer = TextRenderer(options: options)
        let output = NSMutableAttributedString()
        var items: [ConsoleTextItemViewModel] = []
        for entity in entities {
            var viewModel = ConsoleTextItemViewModel()
            let string = render(entity, using: renderer)
            viewModel.range = NSRange(location: output.length, length: string.length)
            output.append(string)
            items.append(viewModel)
        }
        self.items = items
        self.text.display(output)
    }

    private func render(_ entity: NSManagedObject, using renderer: TextRenderer) -> NSAttributedString {
        if let string = cache[entity.objectID] {
            return string
        }
        let string = _render(entity, using: renderer)
        cache[entity.objectID] = string
        return string
    }

    private func _render(_ entity: NSManagedObject, using renderer: TextRenderer) -> NSAttributedString {
        if let task = entity as? NetworkTaskEntity {
            render(task, using: renderer)
        } else if let message = entity as? LoggerMessageEntity {
            if let task = message.task {
                render(task, using: renderer)
            } else {
                render(message, using: renderer)
            }
        } else {
            fatalError("Unsuppported entity: \(entity)")
        }
        return renderer.make()
    }

    private func render(_ message: LoggerMessageEntity, using renderer: TextRenderer) {
        if let task = message.task {
            render(task, using: renderer)
        } else {
            renderer.renderCompact(message)
        }
    }

    private func render(_ task: NetworkTaskEntity, using renderer: TextRenderer) {
        renderer.renderCompact(task)
    }

    func onLinkTapped(_ url: URL) -> Bool {
        if let objectID = list.store.container.persistentStoreCoordinator.managedObjectID(forURIRepresentation: url) {
            router.selection = .entity(objectID)
            return true
        }
        return true
    }
}

#endif