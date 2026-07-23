import pytest

from vision.challenge_counter import classify_availability, parse_counter_text


@pytest.mark.parametrize(
    ("text", "current", "maximum", "capped"),
    [("0/10", 0, 10, False), ("9 / 10", 9, 10, False), ("10/10", 10, 10, True), ("11/10", 11, 10, True)],
)
def test_parse_counter(text, current, maximum, capped):
    assert parse_counter_text(text) == {"current": current, "maximum": maximum, "capped": capped}


def test_invalid_counter_is_rejected():
    with pytest.raises(ValueError):
        parse_counter_text("available")


def test_visible_label_wins_over_counter():
    result = classify_availability(counter={"readable": True, "capped": False}, labels=["completed"])
    assert result == {"available": False, "state": "completed", "source": "visible_label"}


def test_unknown_state_fails_closed():
    assert classify_availability() == {"available": False, "state": "unknown", "source": "unreadable"}

