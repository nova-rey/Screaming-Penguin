"""Pytest fixtures for installer tests."""

import pathlib
import sys

root = pathlib.Path(__file__).resolve().parents[1]
root_path = str(root)
if root_path not in sys.path:
    sys.path.append(root_path)
