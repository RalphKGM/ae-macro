from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

import cv2
import numpy as np


@dataclass(frozen=True)
class Match:
    score: float
    x: int
    y: int
    width: int
    height: int
    scale: float

    def as_dict(self) -> dict[str, float | int]:
        return {
            "score": self.score,
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
            "center_x": self.x + self.width / 2,
            "center_y": self.y + self.height / 2,
            "scale": self.scale,
        }


def read_image(path: str | Path, flags: int = cv2.IMREAD_COLOR) -> np.ndarray:
    image = cv2.imread(str(path), flags)
    if image is None:
        raise ValueError(f"could not read image: {path}")
    return image


def normalize(image: np.ndarray, width: int = 816, height: int = 638) -> np.ndarray:
    if width <= 0 or height <= 0:
        raise ValueError("normalization dimensions must be positive")
    if image.size == 0:
        raise ValueError("cannot normalize an empty image")
    interpolation = cv2.INTER_AREA if image.shape[1] > width or image.shape[0] > height else cv2.INTER_CUBIC
    return cv2.resize(image, (width, height), interpolation=interpolation)


def crop_roi(image: np.ndarray, roi: dict[str, int] | None) -> tuple[np.ndarray, int, int]:
    if not roi:
        return image, 0, 0
    x, y, w, h = (int(roi[key]) for key in ("x", "y", "w", "h"))
    if w <= 0 or h <= 0 or x < 0 or y < 0 or x + w > image.shape[1] or y + h > image.shape[0]:
        raise ValueError("ROI is outside the image")
    return image[y : y + h, x : x + w], x, y


def best_template_match(
    image: np.ndarray,
    template: np.ndarray,
    *,
    roi: dict[str, int] | None = None,
    scales: Iterable[float] = (1.0,),
) -> Match | None:
    search, offset_x, offset_y = crop_roi(image, roi)
    search_gray = cv2.cvtColor(search, cv2.COLOR_BGR2GRAY) if search.ndim == 3 else search
    template_gray = cv2.cvtColor(template, cv2.COLOR_BGR2GRAY) if template.ndim == 3 else template
    best: Match | None = None
    for scale in scales:
        if scale <= 0:
            continue
        width = max(1, round(template_gray.shape[1] * scale))
        height = max(1, round(template_gray.shape[0] * scale))
        if width > search_gray.shape[1] or height > search_gray.shape[0]:
            continue
        resized = cv2.resize(template_gray, (width, height), interpolation=cv2.INTER_AREA)
        result = cv2.matchTemplate(search_gray, resized, cv2.TM_CCOEFF_NORMED)
        _, score, _, location = cv2.minMaxLoc(result)
        candidate = Match(float(score), location[0] + offset_x, location[1] + offset_y, width, height, float(scale))
        if best is None or candidate.score > best.score:
            best = candidate
    return best


def sample_color(image: np.ndarray, x: int, y: int, radius: int = 0) -> dict[str, float]:
    if radius < 0:
        raise ValueError("radius cannot be negative")
    x0, x1 = max(0, x - radius), min(image.shape[1], x + radius + 1)
    y0, y1 = max(0, y - radius), min(image.shape[0], y + radius + 1)
    if x0 >= x1 or y0 >= y1:
        raise ValueError("sample point is outside the image")
    bgr = image[y0:y1, x0:x1].mean(axis=(0, 1))
    return {"r": float(bgr[2]), "g": float(bgr[1]), "b": float(bgr[0])}

