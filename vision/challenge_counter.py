from __future__ import annotations

import re
from pathlib import Path

import cv2
import numpy as np

from .matching import best_template_match, read_image

COUNTER_PATTERN = re.compile(r"^\s*(\d+)\s*/\s*(\d+)\s*$")


def parse_counter_text(text: str) -> dict[str, int | bool]:
    match = COUNTER_PATTERN.match(text)
    if not match:
        raise ValueError(f"not a challenge counter: {text!r}")
    current, maximum = int(match.group(1)), int(match.group(2))
    if maximum <= 0 or current < 0:
        raise ValueError("counter values are invalid")
    return {"current": current, "maximum": maximum, "capped": current >= maximum}


def preprocess_counter(image: np.ndarray) -> np.ndarray:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    gray = cv2.resize(gray, None, fx=3, fy=3, interpolation=cv2.INTER_CUBIC)
    gray = cv2.GaussianBlur(gray, (3, 3), 0)
    return cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)[1]


def load_glyph_templates(directory: str | Path) -> dict[str, np.ndarray]:
    base = Path(directory)
    templates: dict[str, np.ndarray] = {}
    for glyph in [str(value) for value in range(10)] + ["slash"]:
        path = base / f"{glyph}.png"
        if path.exists():
            templates["/" if glyph == "slash" else glyph] = read_image(path, cv2.IMREAD_GRAYSCALE)
    return templates


def recognize_counter(image: np.ndarray, templates: dict[str, np.ndarray], minimum_score: float = 0.55) -> dict:
    if len(templates) < 11:
        return {"readable": False, "reason": "digit templates are incomplete"}
    binary = preprocess_counter(image)
    contours, _ = cv2.findContours(binary, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    boxes = []
    for contour in contours:
        x, y, w, h = cv2.boundingRect(contour)
        if h >= binary.shape[0] * 0.25 and w >= 2:
            boxes.append((x, y, w, h))
    boxes.sort(key=lambda box: box[0])
    symbols: list[str] = []
    scores: list[float] = []
    for x, y, w, h in boxes:
        glyph = binary[y : y + h, x : x + w]
        best_symbol, best_score = None, -1.0
        for symbol, template in templates.items():
            resized = cv2.resize(glyph, (template.shape[1], template.shape[0]), interpolation=cv2.INTER_AREA)
            match = best_template_match(template, resized)
            if match and match.score > best_score:
                best_symbol, best_score = symbol, match.score
        if best_symbol is not None and best_score >= minimum_score:
            symbols.append(best_symbol)
            scores.append(best_score)
    text = "".join(symbols)
    try:
        parsed = parse_counter_text(text)
    except ValueError as error:
        return {"readable": False, "text": text, "reason": str(error), "scores": scores}
    return {"readable": True, "text": text, "confidence": min(scores) if scores else 0.0, **parsed}


def classify_availability(*, counter: dict | None = None, labels: list[str] | None = None) -> dict[str, str | bool]:
    normalized = {label.strip().lower() for label in (labels or [])}
    if any(label in normalized for label in ("locked", "limit reached", "completed")):
        state = "locked" if "locked" in normalized else "completed"
        return {"available": False, "state": state, "source": "visible_label"}
    if counter and counter.get("readable"):
        return {"available": not bool(counter.get("capped")), "state": "capped" if counter.get("capped") else "available", "source": "visible_counter"}
    return {"available": False, "state": "unknown", "source": "unreadable"}

