from pathlib import Path

import cv2
import pytest

from vision.rewards import parse_reward_text, read_rewards


ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "runtime/bin/ae-input"


@pytest.mark.parametrize(
    ("text", "expected"),
    [
        ("2x\nTrait Crystal", {"name": "Trait Crystal", "amount": 2}),
        ("100x\nGoid", {"name": "Gold", "amount": 100}),
        ("5x\nSprite (Crey)", {"name": "Sprite (Grey)", "amount": 5}),
        ("145X\nPLAYER\nEXP\nPlayer EXP", {"name": "Player EXP", "amount": 145}),
    ],
)
def test_reward_ocr_text_is_normalized(text, expected):
    assert parse_reward_text(text) == expected


@pytest.mark.skipif(not HELPER.exists(), reason="native macOS OCR helper is not built")
def test_victory_fixture_rewards_are_read_card_by_card():
    image = cv2.imread(str(ROOT / "tests/fixtures/victory.png"))
    result = read_rewards(image, HELPER)
    assert result["items"] == [
        {"name": "Trait Crystal", "amount": 2},
        {"name": "Gem", "amount": 100},
        {"name": "Gold", "amount": 100},
        {"name": "Sprite (Grey)", "amount": 5},
        {"name": "Unit EXP", "amount": 1000},
        {"name": "Player EXP", "amount": 145},
        {"name": "Mana Flask", "amount": 2},
    ]
