from pathlib import Path

import cv2
import numpy as np
import pytest

from vision.diagnostics import image_metrics
from vision.matching import best_template_match, crop_roi, normalize, sample_color


def test_normalize_to_reference_size():
    image = np.zeros((1178, 2048, 3), dtype=np.uint8)
    result = normalize(image, 816, 638)
    assert result.shape == (638, 816, 3)


def test_template_match_reports_reference_coordinates():
    image = np.zeros((180, 240, 3), dtype=np.uint8)
    cv2.rectangle(image, (73, 51), (112, 90), (255, 255, 255), -1)
    cv2.line(image, (73, 51), (112, 90), (0, 0, 0), 3)
    template = image[51:91, 73:113].copy()
    match = best_template_match(image, template, roi={"x": 40, "y": 30, "w": 140, "h": 110})
    assert match is not None
    assert match.score > 0.99
    assert (match.x, match.y, match.width, match.height) == (73, 51, 40, 40)


def test_invalid_roi_is_rejected():
    with pytest.raises(ValueError, match="ROI"):
        crop_roi(np.zeros((10, 10, 3), dtype=np.uint8), {"x": 9, "y": 9, "w": 2, "h": 2})


def test_color_sample_uses_rgb_names():
    image = np.zeros((5, 5, 3), dtype=np.uint8)
    image[2, 2] = (10, 20, 30)
    assert sample_color(image, 2, 2) == {"r": 30.0, "g": 20.0, "b": 10.0}


def test_solid_capture_is_flagged():
    metrics = image_metrics(np.full((10, 10, 3), 42, dtype=np.uint8))
    assert metrics["blank_or_solid"] is True

