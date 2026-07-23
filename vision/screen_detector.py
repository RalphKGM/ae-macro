from __future__ import annotations

import cv2
import numpy as np


def _roi(image: np.ndarray, bounds: tuple[int, int, int, int]) -> np.ndarray:
    x1, y1, x2, y2 = bounds
    return image[y1:y2, x1:x2]


def _ratios(image: np.ndarray) -> dict[str, float]:
    hsv = cv2.cvtColor(image, cv2.COLOR_BGR2HSV)
    hue, saturation, value = cv2.split(hsv)
    vivid = (saturation > 100) & (value > 80)
    return {
        "cyan": float(((hue >= 80) & (hue <= 105) & vivid).mean()),
        "red": float((((hue < 10) | (hue > 170)) & (saturation > 120) & (value > 100)).mean()),
        "green": float(((hue >= 35) & (hue <= 85) & (saturation > 100) & (value > 90)).mean()),
        "yellow": float(((hue >= 15) & (hue <= 40) & (saturation > 100) & (value > 100)).mean()),
    }


def classify_screen(image: np.ndarray) -> dict:
    if image.shape[1] != 816 or image.shape[0] != 638:
        image = cv2.resize(image, (816, 638), interpolation=cv2.INTER_AREA)

    regions = {
        "lobby_play": _ratios(_roi(image, (35, 350, 115, 430))),
        "lobby_units": _ratios(_roi(image, (0, 245, 115, 330))),
        "afk_title": _ratios(_roi(image, (285, 25, 530, 75))),
        "afk_actions": _ratios(_roi(image, (250, 575, 560, 635))),
        "party_start": _ratios(_roi(image, (390, 400, 510, 440))),
        "party_leave": _ratios(_roi(image, (685, 585, 805, 635))),
        "result_header": _ratios(_roi(image, (90, 145, 720, 215))),
        "start_game": _ratios(_roi(image, (300, 165, 515, 215))),
        "repeat_button": _ratios(_roi(image, (110, 445, 310, 500))),
        "game_results": _ratios(_roi(image, (345, 490, 470, 545))),
        "unit_cards": _ratios(_roi(image, (230, 535, 590, 625))),
        "lobby_modal_close": _ratios(_roi(image, (655, 140, 710, 205))),
    }

    header = regions["result_header"]
    repeat = regions["repeat_button"]["yellow"]
    if (
        regions["lobby_modal_close"]["red"] > 0.06
        and regions["lobby_play"]["cyan"] > 0.04
        and regions["lobby_units"]["cyan"] > 0.02
    ):
        confidence = (
            regions["lobby_modal_close"]["red"] * 4
            + regions["lobby_play"]["cyan"] * 2
        )
        return {
            "state": "lobby_overlay",
            "confidence": min(1.0, confidence),
            "regions": regions,
        }
    if (
        regions["lobby_play"]["cyan"] > 0.09
        and regions["lobby_play"]["green"] > 0.06
        and regions["lobby_units"]["cyan"] > 0.05
        and regions["lobby_units"]["yellow"] > 0.10
    ):
        confidence = (
            regions["lobby_play"]["cyan"] * 2
            + regions["lobby_play"]["green"] * 2
            + regions["lobby_units"]["yellow"]
        )
        return {
            "state": "lobby",
            "confidence": min(1.0, confidence),
            "regions": regions,
        }
    if (
        regions["afk_title"]["yellow"] > 0.05
        and regions["afk_actions"]["yellow"] > 0.18
    ):
        confidence = (
            regions["afk_title"]["yellow"] * 2
            + regions["afk_actions"]["yellow"] * 3
        )
        return {
            "state": "afk_chamber",
            "confidence": min(1.0, confidence),
            "regions": regions,
        }
    if (
        regions["party_start"]["green"] > 0.25
        and regions["party_leave"]["red"] > 0.12
    ):
        confidence = (
            regions["party_start"]["green"]
            + regions["party_leave"]["red"]
        )
        return {
            "state": "party_ready",
            "confidence": min(1.0, confidence),
            "regions": regions,
        }
    if repeat > 0.25 and header["cyan"] > 0.06:
        return {"state": "victory", "confidence": min(1.0, header["cyan"] * 5 + repeat), "regions": regions}
    if repeat > 0.25 and header["red"] > 0.08:
        return {"state": "defeat", "confidence": min(1.0, header["red"] * 4 + repeat), "regions": regions}
    if regions["start_game"]["green"] > 0.2:
        return {"state": "stage_ready", "confidence": min(1.0, regions["start_game"]["green"] * 2.5), "regions": regions}
    if (
        regions["game_results"]["yellow"] > 0.1
        and regions["repeat_button"]["yellow"] > 0.08
    ):
        confidence = regions["game_results"]["yellow"] * 3 + regions["repeat_button"]["yellow"] * 2
        return {"state": "finished_stage", "confidence": min(1.0, confidence), "regions": regions}
    if regions["unit_cards"]["yellow"] > 0.04:
        return {"state": "battle", "confidence": min(0.85, regions["unit_cards"]["yellow"] * 5), "regions": regions}
    return {"state": "unknown", "confidence": 0.0, "regions": regions}
