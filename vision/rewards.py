from __future__ import annotations

import json
import re
import subprocess
import tempfile
from difflib import SequenceMatcher
from pathlib import Path

import cv2
import numpy as np


REFERENCE_WIDTH = 816
REFERENCE_HEIGHT = 638
CARD_BOXES = tuple((140 + 52 * index, 366, 51, 56) for index in range(7))
KNOWN_REWARDS = (
    "Trait Crystal",
    "Gem",
    "Gold",
    "Sprite (Grey)",
    "Unit EXP",
    "Player EXP",
    "Mana Flask",
)


def _compact(value: str) -> str:
    return re.sub(r"[^a-z0-9]+", "", value.lower())


def _canonical_label(lines: list[str]) -> str:
    candidates = [line.strip() for line in lines if line.strip()]
    if not candidates:
        return ""
    joined = " ".join(candidates)
    normalized = (
        joined.replace("Crey", "Grey")
        .replace("Goid", "Gold")
        .replace("Cold", "Gold")
        .replace("Fiask", "Flask")
        .replace("Flack", "Flask")
        .replace("CXP", "EXP")
        .replace("Costal", "Crystal")
    )
    compact = _compact(normalized)
    best_label = ""
    best_score = 0.0
    for label in KNOWN_REWARDS:
        target = _compact(label)
        if target in compact:
            return label
        score = SequenceMatcher(None, compact, target).ratio()
        if score > best_score:
            best_label, best_score = label, score
    if best_score >= 0.58:
        return best_label
    usable = [
        line
        for line in candidates
        if not (line.isupper() and len(line) <= 8)
        and _compact(line) not in {"exp", "unit", "player"}
    ]
    return (usable[-1] if usable else candidates[-1]).strip(" ·•:-")


def parse_reward_text(text: str) -> dict | None:
    lines = [line.strip() for line in str(text or "").splitlines() if line.strip()]
    amount = None
    label_lines: list[str] = []
    for line in lines:
        match = re.fullmatch(r"\s*(\d[\d,]*)\s*[xX×]\s*", line)
        if match and amount is None:
            amount = int(match.group(1).replace(",", ""))
        else:
            label_lines.append(line)
    label = _canonical_label(label_lines)
    if not label or amount is None:
        return None
    return {"name": label, "amount": amount}


def _ocr(helper: Path, image_path: Path) -> str:
    process = subprocess.run(
        [str(helper), "ocr", str(image_path)],
        check=True,
        capture_output=True,
        text=True,
        timeout=20,
    )
    return str(json.loads(process.stdout).get("text", ""))


def read_rewards(image: np.ndarray, helper: str | Path) -> dict:
    if image.shape[1] != REFERENCE_WIDTH or image.shape[0] != REFERENCE_HEIGHT:
        image = cv2.resize(image, (REFERENCE_WIDTH, REFERENCE_HEIGHT), interpolation=cv2.INTER_AREA)
    helper_path = Path(helper)
    items: list[dict] = []
    raw: list[str] = []
    with tempfile.TemporaryDirectory(prefix="ae-rewards-") as temporary:
        root = Path(temporary)
        for index, (x, y, width, height) in enumerate(CARD_BOXES, start=1):
            card = image[y : y + height, x : x + width]
            enlarged = cv2.resize(card, None, fx=5, fy=5, interpolation=cv2.INTER_CUBIC)
            path = root / f"card-{index}.png"
            if not cv2.imwrite(str(path), enlarged):
                continue
            try:
                text = _ocr(helper_path, path)
            except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
                continue
            if text:
                raw.append(text)
            parsed = parse_reward_text(text)
            if parsed:
                items.append(parsed)
    summary = ", ".join(f"{item['amount']}x {item['name']}" for item in items)
    return {"items": items, "summary": summary or "no readable rewards", "raw": raw}
