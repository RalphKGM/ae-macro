from pathlib import Path

import cv2
import numpy as np
import pytest

from vision.screen_detector import classify_screen


FIXTURES = Path(__file__).parents[1] / "fixtures"


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("victory.png", "victory"),
        ("defeat.png", "defeat"),
        ("stage-ready.png", "stage_ready"),
        ("finished-stage.png", "finished_stage"),
        ("battle.png", "battle"),
        ("lobby.png", "lobby"),
    ],
)
def test_live_screen_fixtures(filename: str, expected: str):
    image = cv2.imread(str(FIXTURES / filename))
    assert image is not None
    result = classify_screen(image)
    assert result["state"] == expected
    assert result["confidence"] > 0


def test_afk_chamber_beats_battle_card_false_positive():
    image = np.zeros((638, 816, 3), dtype=np.uint8)
    yellow = (0, 210, 255)
    image[25:75, 285:530] = yellow
    image[575:635, 250:560] = yellow
    image[535:625, 230:590] = yellow

    result = classify_screen(image)

    assert result["state"] == "afk_chamber"
    assert result["confidence"] > 0


def test_party_screen_beats_finished_stage_false_positive():
    image = np.zeros((638, 816, 3), dtype=np.uint8)
    image[400:440, 390:510] = (0, 210, 0)
    image[585:635, 685:805] = (0, 0, 220)
    image[490:545, 345:470] = (0, 210, 255)

    result = classify_screen(image)

    assert result["state"] == "party_ready"
    assert result["confidence"] > 0
