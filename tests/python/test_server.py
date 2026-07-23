from pathlib import Path

import cv2
import numpy as np
import pytest

from vision.server import VisionService


def test_normalize_operation_and_cache(tmp_path: Path):
    source = tmp_path / "raw.png"
    output = tmp_path / "normalized.png"
    diagnostic = tmp_path / "diagnostic.json"
    image = np.zeros((100, 200, 3), dtype=np.uint8)
    cv2.circle(image, (100, 50), 20, (0, 255, 255), -1)
    cv2.imwrite(str(source), image)
    service = VisionService(tmp_path, "secret")

    result = service.execute("normalize", {
        "input_path": str(source), "output_path": str(output), "diagnostic_path": str(diagnostic),
        "width": 816, "height": 638,
    })

    assert output.exists()
    assert diagnostic.exists()
    assert result["width"] == 816
    assert result["height"] == 638
    assert result["blank_or_solid"] is False


def test_paths_cannot_escape_project_root(tmp_path: Path):
    service = VisionService(tmp_path, "secret")
    with pytest.raises(ValueError, match="project root"):
        service.safe_path("/etc/passwd", must_exist=True)


def test_unknown_operation_is_rejected(tmp_path: Path):
    with pytest.raises(ValueError, match="unsupported"):
        VisionService(tmp_path, "secret").execute("launch_missiles", {})

