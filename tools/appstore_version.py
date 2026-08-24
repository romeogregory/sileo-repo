"""mitmproxy addon: make the App Store install an older build of an app you own.

The App Store sends Apple a plist naming the exact build it wants, keyed
`appExtVrsId`. Rewriting that value makes Apple serve a different build of the
same app — Apple still checks your purchase history and still handles the
FairPlay licence, so this only ever reaches versions your Apple ID can already
obtain. It is the same request the App Store would send if its UI had a version
picker.

Two modes, on purpose:

  observe   (default) log any request carrying appExtVrsId, change nothing.
            Run this first. If nothing is logged when you tap download, the
            connection is not interceptable and no amount of tuning the id will
            help — that answer is worth two minutes rather than an evening.

  rewrite   set app_ext_vrs_id and every such request is rewritten.

Usage:
    mitmdump -s tools/appstore_version.py
    mitmdump -s tools/appstore_version.py --set app_ext_vrs_id=846675561

Get the ids with:  ipatool list-versions -b <bundle-id>
"""
from __future__ import annotations

import plistlib
from typing import Any

from mitmproxy import ctx, http

VERSION_KEY = "appExtVrsId"


class AppStoreVersion:
    def load(self, loader: Any) -> None:
        loader.add_option(
            name="app_ext_vrs_id",
            typespec=str,
            default="",
            help="External version id to request. Empty means observe only.",
        )

    # -- plist helpers -----------------------------------------------------

    @staticmethod
    def _parse(body: bytes) -> tuple[Any, Any]:
        """Return (object, format) or (None, None) if this is not a plist."""
        if not body:
            return None, None
        try:
            parsed = plistlib.loads(body)
        except Exception:
            return None, None
        # Re-serialising in the wrong format would change the body far more
        # than the one value we mean to touch.
        fmt = plistlib.FMT_BINARY if body[:8] == b"bplist00" else plistlib.FMT_XML
        return parsed, fmt

    @classmethod
    def _find(cls, node: Any) -> list[Any]:
        """Every value stored under VERSION_KEY, at any depth."""
        found = []
        if isinstance(node, dict):
            for key, value in node.items():
                if key == VERSION_KEY:
                    found.append(value)
                found.extend(cls._find(value))
        elif isinstance(node, list):
            for item in node:
                found.extend(cls._find(item))
        return found

    @classmethod
    def _rewrite(cls, node: Any, new_value: Any) -> int:
        """Replace VERSION_KEY in place. Returns how many were changed."""
        changed = 0
        if isinstance(node, dict):
            for key in list(node.keys()):
                if key == VERSION_KEY:
                    node[key] = new_value
                    changed += 1
                changed += cls._rewrite(node[key], new_value)
        elif isinstance(node, list):
            for item in node:
                changed += cls._rewrite(item, new_value)
        return changed

    # -- hook --------------------------------------------------------------

    def request(self, flow: http.HTTPFlow) -> None:
        # Deliberately not filtered by host or path. Apple has moved these
        # endpoints before, and a filter that is subtly wrong looks exactly like
        # a connection that cannot be intercepted. Parsing every plist body is
        # cheap and cannot produce that false negative.
        parsed, fmt = self._parse(flow.request.content)
        if parsed is None:
            return

        present = self._find(parsed)
        if not present:
            return

        target = ctx.options.app_ext_vrs_id.strip()
        host = flow.request.pretty_host

        if not target:
            ctx.log.alert(
                f"[observe] {VERSION_KEY}={present} on {host}{flow.request.path[:60]}"
            )
            return

        # Apple sends this as an integer in binary plists and a string in XML
        # ones. Matching whatever is already there avoids a type mismatch that
        # would be rejected server-side.
        sample = present[0]
        value = int(target) if isinstance(sample, int) else target

        count = self._rewrite(parsed, value)
        flow.request.content = plistlib.dumps(parsed, fmt=fmt)
        ctx.log.alert(f"[rewrite] {present} -> {value} ({count} field(s)) on {host}")


addons = [AppStoreVersion()]
