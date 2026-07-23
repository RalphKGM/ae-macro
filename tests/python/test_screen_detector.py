from pathlib import Path

import cv2
import numpy as np
import pytest

from vision.screen_detector import classify_screen


FIXTURES = Path(__file__).parents[1] / "fixtures"
TEMPLATES = Path(__file__).parents[2] / "assets" / "nav"


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


@pytest.mark.parametrize(
    ("filename", "expected"),
    [
        ("lobby-overlay.png", "lobby_overlay"),
        ("mode-select.png", "mode_select"),
        ("party-ready-live.png", "party_ready"),
        ("stage-select-live.png", "stage_select"),
    ],
)
def test_v4_templates_identify_live_navigation_checkpoints(filename: str, expected: str):
    image = cv2.imread(str(FIXTURES / filename))
    assert image is not None
    result = classify_screen(image, templates_dir=TEMPLATES)
    assert result["state"] == expected
    assert result["confidence"] >= 0.9


def test_result_context_rejects_lobby_and_mode_screens():
    for filename in (
        "lobby-overlay.png",
        "mode-select.png",
        "party-ready-live.png",
        "stage-select-live.png",
    ):
        image = cv2.imread(str(FIXTURES / filename))
        result = classify_screen(image, templates_dir=TEMPLATES, context="result")
        assert result["state"] == "unknown"


def test_unit_menu_context_uses_the_v4_upgrade_strip_vote():
    image = np.zeros((638, 816, 3), dtype=np.uint8)
    for index in range(8):
        image[386, 158 + index * 9] = (31, 31, 31)
    result = classify_screen(image, context="unit_menu")
    assert result["state"] == "unit_menu"
    assert result["unit_menu_vote"]["grey"] == 8
