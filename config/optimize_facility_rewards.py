#!/usr/bin/env python3
"""Compatibility entry point for the staged facility reward generator.

Facility ordering, realm level caps, and the two-items-per-circulation rule
are now generated together by ``expand_home_meridians.py``.  Keep this
historical command as a thin wrapper so old build instructions do not produce
an invalid partial schedule.
"""

from expand_home_meridians import main


if __name__ == "__main__":
    main()
