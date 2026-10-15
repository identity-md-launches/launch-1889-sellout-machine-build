#!/usr/bin/env python3
"""Independent SVG oracle: expected full-image SHA-256 values for the pinned Vessel renderer.

Uses only Python's standard library. Prints constants used by the mainnet integration tests.
This never contacts a chain or writes to one.
"""

import hashlib

COUNTS = (0, 1, 100, 101, 5000, 9999, 10000)
HEAD = (
    "<svg xmlns='http://www.w3.org/2000/svg' width='600' height='600' "
    "viewBox='0 0 100 100' shape-rendering='crispEdges'>"
)


def expected_svg(count: int) -> bytes:
    pixels = []
    for i in range(10000):
        value = 0 if i < count else 255
        pixels.append(
            f"<rect x='{i % 100}' y='{i // 100}' width='1' height='1' "
            f"fill='rgb({value},{value},{value})'/>"
        )
    return (HEAD + "".join(pixels) + "</svg>").encode("ascii")


if __name__ == "__main__":
    for count in COUNTS:
        svg = expected_svg(count)
        print(count, len(svg), "0x" + hashlib.sha256(svg).hexdigest())
