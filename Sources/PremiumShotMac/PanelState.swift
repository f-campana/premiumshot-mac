import Foundation
import PremiumShotCore

public struct WorkToken: Equatable, Sendable {
    public let sessionID: UUID?
    public let revision: UInt64
    public let epoch: UInt64
}

/// Pure transition state; windows and asynchronous workers cannot mutate it.
public struct PanelState: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case hidden
        case empty(String?)
        case alreadyPolished
        case ready(UUID)
    }
    public private(set) var mode: Mode = .hidden
    public private(set) var recipe: Recipe = .default
    public private(set) var revision: UInt64 = 0
    public private(set) var epoch: UInt64 = 0
    public var drawer = false, inspect = false
    public var importing = false
    public init() {}
    public var sessionID: UUID? {
        if case .ready(let id) = mode { return id }
        return nil
    }
    public var token: WorkToken { WorkToken(sessionID: sessionID, revision: revision, epoch: epoch) }
    public mutating func transition(to mode: Mode, recipe: Recipe? = nil) {
        epoch &+= 1
        self.mode = mode
        importing = false
        if let recipe {
            self.recipe = recipe
            revision &+= 1
        }
        if case .ready = mode {
        } else {
            drawer = false
            inspect = false
        }
    }
    public mutating func changeRecipe(_ value: Recipe) {
        guard value != recipe else { return }
        recipe = value
        revision &+= 1
    }
    public mutating func invalidate() {
        epoch &+= 1
        importing = false
    }
}

public struct StyleHistory: Sendable {
    private var undoStack: [Recipe] = [], redoStack: [Recipe] = []
    private var dragStart: Recipe?
    public init() {}
    public mutating func beginDrag(_ recipe: Recipe) { dragStart = recipe }
    public mutating func endDrag(_ current: Recipe) {
        if let before = dragStart {
            dragStart = nil
            record(before: before, after: current)
        }
    }
    public mutating func record(before: Recipe, after: Recipe) {
        guard dragStart == nil, before != after else { return }
        undoStack.append(before)
        if undoStack.count > 100 { undoStack.removeFirst() }
        redoStack = []
    }
    public mutating func undo(_ current: Recipe) -> Recipe? {
        guard let value = undoStack.popLast() else { return nil }
        redoStack.append(current)
        return value
    }
    public mutating func redo(_ current: Recipe) -> Recipe? {
        guard let value = redoStack.popLast() else { return nil }
        undoStack.append(current)
        return value
    }
}

public enum KeyRouting {
    public static func shouldRemove(
        keyCode: UInt16, hasModifiers: Bool, previewFocused: Bool, inspecting: Bool
    ) -> Bool {
        [51, 117].contains(keyCode) && !hasModifiers && previewFocused && !inspecting
    }
}
