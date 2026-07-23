from __future__ import annotations

import argparse
import hmac
import json
import socketserver
import subprocess
import sys
import traceback
from pathlib import Path
from typing import Any

import cv2

from .challenge_counter import classify_availability, counters_from_text, load_glyph_templates, recognize_counter
from .diagnostics import annotated_match, image_metrics, write_json
from .matching import best_template_match, normalize, read_image, sample_color
from .screen_detector import classify_screen


class VisionService:
    def __init__(self, root: Path, token: str):
        self.root = root.resolve()
        self.token = token
        self.cached_path: Path | None = None

    def safe_path(self, value: str, *, must_exist: bool = False) -> Path:
        path = Path(value).expanduser()
        if not path.is_absolute():
            path = self.root / path
        path = path.resolve()
        if path != self.root and self.root not in path.parents:
            raise ValueError("path must remain inside the project root")
        if must_exist and not path.exists():
            raise ValueError(f"path does not exist: {path}")
        return path

    def execute(self, operation: str, payload: dict[str, Any]) -> dict[str, Any]:
        if operation == "ping":
            return {"service": "anime-expeditions-vision", "version": "0.1.0"}
        if operation == "normalize":
            return self.normalize(payload)
        if operation == "match":
            return self.match(payload)
        if operation == "sample_color":
            return self.color(payload)
        if operation == "challenge_counter":
            return self.challenge_counter(payload)
        if operation == "ocr_text":
            return self.ocr_text(payload)
        if operation == "classify_screen":
            return self.classify_screen(payload)
        raise ValueError(f"unsupported operation: {operation}")

    def normalize(self, payload: dict[str, Any]) -> dict[str, Any]:
        source = self.safe_path(payload["input_path"], must_exist=True)
        output = self.safe_path(payload["output_path"])
        image = read_image(source)
        insets = payload.get("insets") or {}
        left, right = int(insets.get("left", 0)), int(insets.get("right", 0))
        top, bottom = int(insets.get("top", 0)), int(insets.get("bottom", 0))
        if any(value < 0 for value in (left, right, top, bottom)):
            raise ValueError("capture insets cannot be negative")
        if left + right >= image.shape[1] or top + bottom >= image.shape[0]:
            raise ValueError("capture insets remove the entire image")
        cropped = image[top : image.shape[0] - bottom or None, left : image.shape[1] - right or None]
        normalized = normalize(cropped, int(payload.get("width", 816)), int(payload.get("height", 638)))
        output.parent.mkdir(parents=True, exist_ok=True)
        if not cv2.imwrite(str(output), normalized):
            raise ValueError("failed to write normalized image")
        self.cached_path = output
        metrics = image_metrics(normalized)
        result = {"input_path": str(source), "output_path": str(output), **metrics}
        if payload.get("diagnostic_path"):
            diagnostic = self.safe_path(payload["diagnostic_path"])
            write_json(diagnostic, result)
            result["diagnostic_path"] = str(diagnostic)
        return result

    def image_for(self, payload: dict[str, Any]):
        requested = payload.get("image_path")
        path = self.safe_path(requested, must_exist=True) if requested else self.cached_path
        if not path or not path.exists():
            raise ValueError("no cached image; normalize or provide image_path first")
        return read_image(path), path

    def match(self, payload: dict[str, Any]) -> dict[str, Any]:
        image, image_path = self.image_for(payload)
        template_path = self.safe_path(payload["template_path"], must_exist=True)
        template = read_image(template_path, cv2.IMREAD_UNCHANGED)
        match = best_template_match(image, template, roi=payload.get("roi"), scales=payload.get("scales", [1.0]))
        if match is None:
            return {"matched": False, "reason": "template does not fit search region"}
        threshold = float(payload.get("threshold", 0.86))
        result = {"matched": match.score >= threshold, "threshold": threshold, "image_path": str(image_path), "template_path": str(template_path), **match.as_dict()}
        if payload.get("diagnostic_path"):
            diagnostic = self.safe_path(payload["diagnostic_path"])
            diagnostic.parent.mkdir(parents=True, exist_ok=True)
            cv2.imwrite(str(diagnostic), annotated_match(image, match, template_path.stem))
            result["diagnostic_path"] = str(diagnostic)
        return result

    def color(self, payload: dict[str, Any]) -> dict[str, Any]:
        image, _ = self.image_for(payload)
        return sample_color(image, int(payload["x"]), int(payload["y"]), int(payload.get("radius", 0)))

    def challenge_counter(self, payload: dict[str, Any]) -> dict[str, Any]:
        image, image_path = self.image_for(payload)
        roi = payload.get("roi")
        if roi:
            x, y, w, h = (int(roi[key]) for key in ("x", "y", "w", "h"))
            image = image[y : y + h, x : x + w]
        templates = load_glyph_templates(self.safe_path(payload.get("templates_dir", "assets/challenge/digits")))
        counter = recognize_counter(image, templates, float(payload.get("minimum_score", 0.55)))
        ocr = None
        if not counter.get("readable"):
            try:
                ocr = self.ocr_text({"image_path": str(image_path), "roi": roi})
                counters = counters_from_text(ocr.get("text", ""))
                if not counters and roi:
                    ocr = self.ocr_text({"image_path": str(image_path)})
                    counters = counters_from_text(ocr.get("text", ""))
                if counters:
                    selected = counters[0]
                    counter = {
                        "readable": True,
                        "text": selected["text"],
                        "current": selected["current"],
                        "maximum": selected["maximum"],
                        "capped": selected["capped"],
                        "confidence": ocr.get("minimum_confidence", 0.0),
                        "source": "native_ocr",
                    }
            except (OSError, ValueError, subprocess.SubprocessError, json.JSONDecodeError) as error:
                ocr = {"error": str(error)}
        labels = list(payload.get("labels") or [])
        if ocr:
            labels.extend(str(line.get("text", "")) for line in (ocr.get("lines") or []))
        return {
            "counter": counter,
            "availability": classify_availability(counter=counter, labels=labels),
            "ocr": ocr,
        }

    def ocr_text(self, payload: dict[str, Any]) -> dict[str, Any]:
        _, image_path = self.image_for(payload)
        helper = self.safe_path("runtime/bin/ae-input", must_exist=True)
        command = [str(helper), "ocr", str(image_path)]
        roi = payload.get("roi")
        if roi:
            command.extend(str(int(roi[key])) for key in ("x", "y", "w", "h"))
        process = subprocess.run(
            command,
            check=True,
            capture_output=True,
            text=True,
            timeout=20,
            cwd=self.root,
        )
        result = json.loads(process.stdout)
        lines = result.get("lines") or []
        confidences = [float(line.get("confidence", 0.0)) for line in lines]
        result["minimum_confidence"] = min(confidences) if confidences else 0.0
        result["image_path"] = str(image_path)
        return result

    def classify_screen(self, payload: dict[str, Any]) -> dict[str, Any]:
        image, image_path = self.image_for(payload)
        templates = self.safe_path(payload.get("templates_dir", "assets/nav"), must_exist=True)
        return {
            "image_path": str(image_path),
            **classify_screen(image, templates_dir=templates, context=payload.get("context")),
        }


class Handler(socketserver.StreamRequestHandler):
    def handle(self) -> None:
        service: VisionService = self.server.service  # type: ignore[attr-defined]
        for raw in self.rfile:
            request_id = None
            try:
                request = json.loads(raw.decode("utf-8"))
                request_id = request.get("id")
                if not hmac.compare_digest(str(request.get("token", "")), service.token):
                    raise PermissionError("invalid worker token")
                result = service.execute(str(request.get("op", "")), request.get("payload") or {})
                response = {"id": request_id, "ok": True, "result": result}
            except Exception as error:
                response = {"id": request_id, "ok": False, "error": f"{type(error).__name__}: {error}"}
            self.wfile.write((json.dumps(response, separators=(",", ":")) + "\n").encode("utf-8"))


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True
    daemon_threads = True


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Anime Expeditions local vision worker")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=47681)
    parser.add_argument("--token", required=True)
    parser.add_argument("--root", type=Path, required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    if args.host not in {"127.0.0.1", "localhost", "::1"}:
        print("Refusing to bind vision worker outside loopback", file=sys.stderr)
        return 2
    service = VisionService(args.root, args.token)
    try:
        with Server((args.host, args.port), Handler) as server:
            server.service = service  # type: ignore[attr-defined]
            print(f"vision worker listening on {args.host}:{args.port}", flush=True)
            server.serve_forever()
    except KeyboardInterrupt:
        return 0
    except Exception:
        traceback.print_exc()
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
