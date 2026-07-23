import CoreGraphics
import Foundation

enum InputError: Error, CustomStringConvertible {
    case usage(String)
    case event(String)

    var description: String {
        switch self {
        case .usage(let message), .event(let message): return message
        }
    }
}

func number(_ value: String, _ label: String) throws -> Double {
    guard let parsed = Double(value) else { throw InputError.usage("invalid \(label): \(value)") }
    return parsed
}

func postMouse(_ type: CGEventType, at point: CGPoint, button: CGMouseButton) throws {
    // A nil source mirrors CGEventCreateMouseEvent(NULL, ...) used by cliclick.
    // Roblox accepts those system-sourced HID events, while a private HID source
    // can be ignored specifically for held right-button camera drags.
    guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: button) else {
        throw InputError.event("could not create mouse event")
    }
    event.post(tap: .cghidEventTap)
}

func rightDrag(arguments: ArraySlice<String>) throws {
    guard arguments.count == 5 else {
        throw InputError.usage("usage: ae-input right-drag x1 y1 x2 y2 duration_ms")
    }
    let values = try arguments.enumerated().map { index, value in
        try number(value, ["x1", "y1", "x2", "y2", "duration_ms"][index])
    }
    let start = CGPoint(x: values[0], y: values[1])
    let finish = CGPoint(x: values[2], y: values[3])
    let duration = max(values[4], 40) / 1000
    let steps = max(Int(duration * 60), 4)

    try postMouse(.mouseMoved, at: start, button: .right)
    Thread.sleep(forTimeInterval: 0.12)
    try postMouse(.rightMouseDown, at: start, button: .right)
    for step in 1...steps {
        let progress = Double(step) / Double(steps)
        let point = CGPoint(
            x: start.x + (finish.x - start.x) * progress,
            y: start.y + (finish.y - start.y) * progress
        )
        try postMouse(.rightMouseDragged, at: point, button: .right)
        Thread.sleep(forTimeInterval: duration / Double(steps))
    }
    try postMouse(.rightMouseUp, at: finish, button: .right)
}

func scroll(arguments: ArraySlice<String>, source: CGEventSource) throws {
    guard arguments.count == 1, let delta = Int32(arguments.first!) else {
        throw InputError.usage("usage: ae-input scroll delta")
    }
    guard let event = CGEvent(
        scrollWheelEvent2Source: source,
        units: .line,
        wheelCount: 1,
        wheel1: delta,
        wheel2: 0,
        wheel3: 0
    ) else { throw InputError.event("could not create scroll event") }
    event.post(tap: .cghidEventTap)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw InputError.usage("missing command") }
    guard let source = CGEventSource(stateID: .hidSystemState) else {
        throw InputError.event("could not create HID event source")
    }
    switch command {
    case "right-drag": try rightDrag(arguments: arguments.dropFirst())
    case "scroll": try scroll(arguments: arguments.dropFirst(), source: source)
    default: throw InputError.usage("unsupported command: \(command)")
    }
} catch {
    FileHandle.standardError.write(("ae-input: \(error)\n").data(using: .utf8)!)
    exit(2)
}
