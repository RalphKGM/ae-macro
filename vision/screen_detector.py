from __future__ import annotations

from functools import lru_cache
from pathlib import Path

import cv2
import numpy as np

from .matching import best_template_match, read_image


REFERENCE_WIDTH = 816
REFERENCE_HEIGHT = 638
SCALES = (1.0, 0.92, 1.09, 0.85, 1.15)


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


@lru_cache(maxsize=64)
def _template(path: str) -> np.ndarray:
    return read_image(path, cv2.IMREAD_UNCHANGED)


def _match(
    image: np.ndarray,
    templates_dir: Path | None,
    name: str,
    *,
    roi: dict[str, int] | None = None,
    scales: tuple[float, ...] = SCALES,
) -> dict | None:
    if templates_dir is None:
        return None
    path = templates_dir / name
    if not path.exists():
        return None
    found = best_template_match(image, _template(str(path)), roi=roi, scales=scales)
    return found.as_dict() if found else None


def _matched(match: dict | None, threshold: float) -> bool:
    return bool(match and float(match["score"]) >= threshold)


def _near(match: dict | None, x: float, y: float, tolerance: float) -> bool:
    return bool(
        match
        and abs(float(match["center_x"]) - x) <= tolerance
        and abs(float(match["center_y"]) - y) <= tolerance
    )


def _template_regions(image: np.ndarray, templates_dir: Path | None) -> dict[str, dict | None]:
    lobby_rois = {
        "lobby_units": {"x": 0, "y": 255, "w": 62, "h": 98},
        "lobby_items": {"x": 48, "y": 255, "w": 64, "h": 98},
        "lobby_quests": {"x": 0, "y": 310, "w": 62, "h": 92},
        "lobby_summon": {"x": 48, "y": 310, "w": 64, "h": 92},
        "lobby_play": {"x": 48, "y": 355, "w": 64, "h": 98},
    }
    matches: dict[str, dict | None] = {}
    for name, roi in lobby_rois.items():
        matches[name] = _match(image, templates_dir, f"{name}.png", roi=roi)
    matches["invite_players"] = _match(
        image, templates_dir, "invite_players.png", roi={"x": 525, "y": 560, "w": 180, "h": 78}
    )
    matches["join_party"] = _match(
        image, templates_dir, "join_party.png", roi={"x": 650, "y": 560, "w": 166, "h": 78}
    )
    matches["start_party"] = _match(
        image, templates_dir, "start_party.png", roi={"x": 320, "y": 335, "w": 270, "h": 145}
    )
    matches["start_game"] = _match(
        image, templates_dir, "start_game.png", roi={"x": 245, "y": 75, "w": 326, "h": 210}
    )
    matches["retry"] = _match(
        image, templates_dir, "retry.png", roi={"x": 70, "y": 410, "w": 300, "h": 145}
    )
    matches["view_party"] = _match(
        image, templates_dir, "view_party.png", roi={"x": 70, "y": 390, "w": 675, "h": 190}
    )
    matches["victory"] = _match(
        image, templates_dir, "victory.png", roi={"x": 45, "y": 95, "w": 725, "h": 175}
    )
    matches["disconnected"] = _match(
        image, templates_dir, "disconnected.png", roi={"x": 140, "y": 120, "w": 540, "h": 300}
    )
    return matches


def _result_color_vote(image: np.ndarray) -> tuple[int, int]:
    blue = red = 0
    for x in range(178, 259, 10):
        for y in range(138, 187, 8):
            b, g, r = (int(value) for value in image[y, x])
            if b > 150 and b > r + 60:
                blue += 1
            elif r > 140 and r > b + 60:
                red += 1
    return blue, red


def classify_screen(
    image: np.ndarray,
    *,
    templates_dir: str | Path | None = None,
    context: str | None = None,
) -> dict:
    if image.shape[1] != REFERENCE_WIDTH or image.shape[0] != REFERENCE_HEIGHT:
        image = cv2.resize(image, (REFERENCE_WIDTH, REFERENCE_HEIGHT), interpolation=cv2.INTER_AREA)

    template_root = Path(templates_dir) if templates_dir else None
    templates = _template_regions(image, template_root)
    retry_is_result = _matched(templates["retry"], 0.89) and _near(templates["retry"], 210, 472, 24)
    party_is_result = _matched(templates["view_party"], 0.89) and _near(templates["view_party"], 415, 468, 42)
    result_controls = max(
        float((templates["retry"] or {}).get("score", 0.0)) if retry_is_result else 0.0,
        float((templates["view_party"] or {}).get("score", 0.0)) if party_is_result else 0.0,
    )
    if result_controls > 0:
        victory_score = float((templates["victory"] or {}).get("score", 0.0))
        blue, red = _result_color_vote(image)
        if victory_score >= 0.93 or (blue >= 4 and blue > red):
            return {
                "state": "victory",
                "confidence": max(victory_score, result_controls),
                "templates": templates,
                "result_vote": {"blue": blue, "red": red},
            }
        if red >= 4 and red > blue:
            return {
                "state": "defeat",
                "confidence": result_controls,
                "templates": templates,
                "result_vote": {"blue": blue, "red": red},
            }

    if context == "result":
        return {
            "state": "unknown",
            "confidence": result_controls,
            "templates": templates,
        }

    if _matched(templates["disconnected"], 0.94):
        return {
            "state": "disconnected",
            "confidence": templates["disconnected"]["score"],
            "templates": templates,
        }

    if _matched(templates["start_game"], 0.90) and _near(templates["start_game"], 408, 193, 38):
        return {
            "state": "stage_ready",
            "confidence": templates["start_game"]["score"],
            "templates": templates,
        }

    if _matched(templates["start_party"], 0.88) and _near(templates["start_party"], 450, 420, 42):
        return {
            "state": "party_ready",
            "confidence": templates["start_party"]["score"],
            "templates": templates,
        }

    if (
        _matched(templates["invite_players"], 0.85)
        and _near(templates["invite_players"], 624, 612, 34)
        and _matched(templates["join_party"], 0.85)
        and _near(templates["join_party"], 746, 609, 34)
    ):
        return {
            "state": "mode_select",
            "confidence": min(templates["invite_players"]["score"], templates["join_party"]["score"]),
            "templates": templates,
        }

    lobby_hits = {
        name: match
        for name, match in templates.items()
        if name.startswith("lobby_") and _matched(match, 0.95)
    }

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

    if len(lobby_hits) >= 3:
        confidence = sum(float(hit["score"]) for hit in lobby_hits.values()) / len(lobby_hits)
        if regions["lobby_modal_close"]["red"] > 0.06:
            return {
                "state": "lobby_overlay",
                "confidence": confidence,
                "templates": templates,
                "regions": regions,
            }
        return {
            "state": "lobby",
            "confidence": confidence,
            "templates": templates,
            "regions": regions,
        }

    if (
        regions["lobby_modal_close"]["red"] > 0.06
        and regions["lobby_play"]["cyan"] > 0.04
        and regions["lobby_units"]["cyan"] > 0.02
    ):
        confidence = regions["lobby_modal_close"]["red"] * 4 + regions["lobby_play"]["cyan"] * 2
        return {"state": "lobby_overlay", "confidence": min(1.0, confidence), "regions": regions}
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
        return {"state": "lobby", "confidence": min(1.0, confidence), "regions": regions}
    if regions["afk_title"]["yellow"] > 0.05 and regions["afk_actions"]["yellow"] > 0.18:
        confidence = regions["afk_title"]["yellow"] * 2 + regions["afk_actions"]["yellow"] * 3
        return {"state": "afk_chamber", "confidence": min(1.0, confidence), "regions": regions}
    if regions["party_start"]["green"] > 0.25 and regions["party_leave"]["red"] > 0.12:
        confidence = regions["party_start"]["green"] + regions["party_leave"]["red"]
        return {"state": "party_ready", "confidence": min(1.0, confidence), "regions": regions}

    repeat = regions["repeat_button"]["yellow"]
    header = regions["result_header"]
    if repeat > 0.25 and header["cyan"] > 0.06:
        return {"state": "victory", "confidence": min(1.0, header["cyan"] * 5 + repeat), "regions": regions}
    if repeat > 0.25 and header["red"] > 0.08:
        return {"state": "defeat", "confidence": min(1.0, header["red"] * 4 + repeat), "regions": regions}
    if regions["start_game"]["green"] > 0.2:
        return {"state": "stage_ready", "confidence": min(1.0, regions["start_game"]["green"] * 2.5), "regions": regions}
    if regions["game_results"]["yellow"] > 0.1 and regions["repeat_button"]["yellow"] > 0.08:
        confidence = regions["game_results"]["yellow"] * 3 + regions["repeat_button"]["yellow"] * 2
        return {"state": "finished_stage", "confidence": min(1.0, confidence), "regions": regions}
    if regions["unit_cards"]["yellow"] > 0.04:
        return {"state": "battle", "confidence": min(0.85, regions["unit_cards"]["yellow"] * 5), "regions": regions}
    return {"state": "unknown", "confidence": 0.0, "templates": templates, "regions": regions}
