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

func scroll(arguments: ArraySlice<String>) throws {
    guard arguments.count == 1, let delta = Int32(arguments.first!) else {
        throw InputError.usage("usage: ae-input scroll delta")
    }
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
        let bottomY = cgImage.height - y - height
        guard let cropped = cgImage.cropping(to: CGRect(x: x, y: bottomY, width: width, height: height)) else {
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
    case "ocr": try recognizeText(arguments: arguments.dropFirst())
    default: throw InputError.usage("unsupported command: \(command)")
    }
} catch {
    FileHandle.standardError.write(("ae-input: \(error)\n").data(using: .utf8)!)
    exit(2)
}
