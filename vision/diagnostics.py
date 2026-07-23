from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import cv2
import numpy as np

from .matching import Match


def image_metrics(image: np.ndarray) -> dict[str, Any]:
    gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY) if image.ndim == 3 else image
    return {
        "width": int(image.shape[1]),
        "height": int(image.shape[0]),
        "mean": float(gray.mean()),
        "stddev": float(gray.std()),
        "minimum": int(gray.min()),
        "maximum": int(gray.max()),
        "blank_or_solid": bool(gray.std() < 2.0),
    }


def annotated_match(image: np.ndarray, match: Match, label: str) -> np.ndarray:
    output = image.copy()
    cv2.rectangle(output, (match.x, match.y), (match.x + match.width, match.y + match.height), (0, 255, 0), 2)
    cv2.putText(output, f"{label} {match.score:.3f}", (match.x, max(16, match.y - 5)), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (0, 255, 0), 1, cv2.LINE_AA)
    return output


def write_json(path: str | Path, payload: dict[str, Any]) -> None:
    destination = Path(path)
    destination.parent.mkdir(parents=True, exist_ok=True)
    temporary = destination.with_suffix(destination.suffix + ".tmp")
    temporary.write_text(json.dumps(payload, indent=2, sort_keys=True), encoding="utf-8")
    temporary.replace(destination)

