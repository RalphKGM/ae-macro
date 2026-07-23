import AppKit
import CoreGraphics
import Foundation
import Vision

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

func move(arguments: ArraySlice<String>) throws {
    guard arguments.count == 5 else {
        throw InputError.usage("usage: ae-input move x1 y1 x2 y2 duration_ms")
    }
    let values = try arguments.enumerated().map { index, value in
        try number(value, ["x1", "y1", "x2", "y2", "duration_ms"][index])
    }
    let start = CGPoint(x: values[0], y: values[1])
    let finish = CGPoint(x: values[2], y: values[3])
    let duration = max(values[4], 40) / 1000
    let steps = max(Int(duration * 60), 4)

    try postMouse(.mouseMoved, at: start, button: .left)
    for step in 1...steps {
        let progress = Double(step) / Double(steps)
        let point = CGPoint(
            x: start.x + (finish.x - start.x) * progress,
            y: start.y + (finish.y - start.y) * progress
        )
        try postMouse(.mouseMoved, at: point, button: .left)
        Thread.sleep(forTimeInterval: duration / Double(steps))
    }
}

func postScroll(_ delta: Int32) throws {
    guard let event = CGEvent(
        scrollWheelEvent2Source: nil,
        units: .line,
        wheelCount: 1,
        wheel1: delta,
        wheel2: 0,
        wheel3: 0
    ) else { throw InputError.event("could not create scroll event") }
    event.post(tap: .cghidEventTap)
}

func scroll(arguments: ArraySlice<String>) throws {
    guard arguments.count == 1, let delta = Int32(arguments.first!) else {
        throw InputError.usage("usage: ae-input scroll delta")
    }
    try postScroll(delta)
}

func zoom(arguments: ArraySlice<String>) throws {
    guard arguments.count == 3 else {
        throw InputError.usage("usage: ae-input zoom key wheel_delta duration_ms")
    }
    let values = Array(arguments)
    let keyCodes: [String: CGKeyCode] = ["i": 34, "o": 31]
    guard let keyCode = keyCodes[values[0].lowercased()] else {
        throw InputError.usage("zoom key must be i or o")
    }
    let delta = Int32(try integer(values[1], "wheel_delta"))
    let duration = max(try integer(values[2], "duration_ms"), 80)
    guard let keyDown = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: true),
          let keyUp = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: false) else {
        throw InputError.event("could not create zoom key events")
    }
    keyDown.post(tap: .cghidEventTap)
    defer { keyUp.post(tap: .cghidEventTap) }
    var elapsed = 0
    while elapsed < duration {
        try postScroll(delta)
        Thread.sleep(forTimeInterval: 0.08)
        elapsed += 80
    }
}

func pitchDown(arguments: ArraySlice<String>) throws {
    guard arguments.count == 4 else {
        throw InputError.usage("usage: ae-input pitch-down x y steps delta_y")
    }
    let values = Array(arguments)
    let x = try number(values[0], "x")
    let y = try number(values[1], "y")
    let steps = max(try integer(values[2], "steps"), 1)
    let deltaY = Int64(try integer(values[3], "delta_y"))
    let point = CGPoint(x: x, y: y)
    try postMouse(.mouseMoved, at: point, button: .right)
    Thread.sleep(forTimeInterval: 0.08)
    try postMouse(.rightMouseDown, at: point, button: .right)
    Thread.sleep(forTimeInterval: 0.12)
    defer { try? postMouse(.rightMouseUp, at: point, button: .right) }
    for _ in 0..<steps {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: .rightMouseDragged,
            mouseCursorPosition: point,
            mouseButton: .right
        ) else { throw InputError.event("could not create camera pitch event") }
        event.setIntegerValueField(.mouseEventDeltaX, value: 0)
        event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
        event.post(tap: .cghidEventTap)
        Thread.sleep(forTimeInterval: 0.012)
    }
    Thread.sleep(forTimeInterval: 0.12)
}

func integer(_ value: String, _ label: String) throws -> Int {
    guard let parsed = Int(value) else { throw InputError.usage("invalid \(label): \(value)") }
    return parsed
}

func recognizeText(arguments: ArraySlice<String>) throws {
    guard arguments.count == 1 || arguments.count == 5 else {
        throw InputError.usage("usage: ae-input ocr image_path [x y width height]")
    }
    let values = Array(arguments)
    let path = values[0]
    guard let image = NSImage(contentsOfFile: path) else {
        throw InputError.event("could not load image: \(path)")
    }
    var proposed = CGRect(origin: .zero, size: image.size)
    guard var cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
        throw InputError.event("could not decode image: \(path)")
    }
    if values.count == 5 {
        let x = try integer(values[1], "x")
        let y = try integer(values[2], "y")
        let width = try integer(values[3], "width")
        let height = try integer(values[4], "height")
        guard x >= 0, y >= 0, width > 0, height > 0,
              x + width <= cgImage.width, y + height <= cgImage.height else {
            throw InputError.usage("ocr region is outside the image")
        }
        // CGImage cropping uses the image-data origin here. The runtime sends
        // top-left screen coordinates, so using y directly keeps OCR ROIs
        // aligned with the normalized 816×638 frame.
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: y, width: width, height: height)) else {
            throw InputError.event("could not crop ocr region")
        }
        cgImage = cropped
    }

    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.recognitionLanguages = ["en-US"]
    request.usesLanguageCorrection = false
    request.minimumTextHeight = 0.015
    let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
    try handler.perform([request])

    var lines: [[String: Any]] = []
    for observation in request.results ?? [] {
        guard let candidate = observation.topCandidates(1).first else { continue }
        lines.append([
            "text": candidate.string,
            "confidence": candidate.confidence,
            "x": observation.boundingBox.origin.x,
            "y": observation.boundingBox.origin.y,
            "width": observation.boundingBox.width,
            "height": observation.boundingBox.height,
        ])
    }
    let output: [String: Any] = [
        "text": lines.compactMap { $0["text"] as? String }.joined(separator: "\n"),
        "lines": lines,
    ]
    let data = try JSONSerialization.data(withJSONObject: output, options: [])
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write("\n".data(using: .utf8)!)
}

do {
    let arguments = Array(CommandLine.arguments.dropFirst())
    guard let command = arguments.first else { throw InputError.usage("missing command") }
    switch command {
    case "move": try move(arguments: arguments.dropFirst())
    case "right-drag": try rightDrag(arguments: arguments.dropFirst())
    case "scroll": try scroll(arguments: arguments.dropFirst())
    case "zoom": try zoom(arguments: arguments.dropFirst())
    case "pitch-down": try pitchDown(arguments: arguments.dropFirst())
    case "ocr": try recognizeText(arguments: arguments.dropFirst())
    default: throw InputError.usage("unsupported command: \(command)")
    }
} catch {
    FileHandle.standardError.write(("ae-input: \(error)\n").data(using: .utf8)!)
    exit(2)
}
