"""
Client network address resolution behind trusted proxies.

The source is explicit configuration, never platform detection:

1. CLIENT_IP_HEADER: a header that the platform's edge proxy always sets
   itself (overwriting anything the client sent), e.g. Railway's X-Real-IP.
   Its value is used as the client address; for a comma-separated list the
   left-most entry is taken. Only safe when the edge really overwrites the
   header — verify with a real request after deploying.
2. TRUSTED_PROXY_HOPS: X-Forwarded-For is a comma-separated list that every
   proxy APPENDS to, so the left-most entries are whatever the client chose to
   send and cannot be trusted. With N trusted proxies in front of the app, the
   real client address is the N-th entry from the right.
3. Otherwise the TCP peer address.

Every fallback is to the peer address. Behind a platform proxy that is the
proxy itself, so requests that did not come through the edge as expected share
one guest allowance: a misconfiguration makes the allowance stricter, never
looser, and is logged (without any address) so it can be noticed.

Addresses are only used in memory (rate limits, keyed guest-quota hashes) and
are never stored or logged.
"""

import ipaddress
import logging
from typing import Optional

from fastapi import Request

from backend.app.config import settings

logger = logging.getLogger("coinscan.client_ip")

_warned_about_header = False


def _valid_ip(value: str) -> Optional[str]:
    candidate = value.strip()
    try:
        address = ipaddress.ip_address(candidate)
    except ValueError:
        return None
    # ::ffff:198.51.100.7 is the same client as 198.51.100.7.
    if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped:
        address = address.ipv4_mapped
    return str(address)


def _warn_edge_header_unusable(header_name: str, reason: str) -> None:
    global _warned_about_header
    if not _warned_about_header:
        _warned_about_header = True
        logger.warning(
            f"CLIENT_IP_HEADER {header_name} is {reason} on an incoming request; using the "
            "connecting address instead. Check that the platform edge sets this header."
        )


def network_bucket(ip: str) -> str:
    """The unit that shares one guest network allowance.

    An IPv4 address is one bucket. An IPv6 client normally controls a whole /64
    and can switch addresses inside it at will, so the /64 is the bucket.
    """
    try:
        address = ipaddress.ip_address(ip)
    except ValueError:
        return ip
    if isinstance(address, ipaddress.IPv6Address):
        return str(ipaddress.IPv6Network(f"{address}/64", strict=False))
    return str(address)


def get_client_ip(request: Request) -> str:
    """Returns the client address as seen by the outermost trusted proxy."""
    peer = request.client.host if request.client else "0.0.0.0"

    header_name = (settings.client_ip_header or "").strip()
    if header_name:
        values = request.headers.getlist(header_name)
        if len(values) != 1:
            # Missing, or sent more than once (one copy may be the client's own):
            # the request did not come through the edge proxy as expected.
            _warn_edge_header_unusable(header_name, "missing" if not values else "repeated")
            return _valid_ip(peer) or peer
        address = _valid_ip(values[0].split(",")[0])
        if address is None:
            _warn_edge_header_unusable(header_name, "not a valid address")
            return _valid_ip(peer) or peer
        return address

    hops = max(0, int(settings.trusted_proxy_hops or 0))
    if hops == 0:
        return peer

    header = request.headers.get("x-forwarded-for", "")
    entries = [e for e in (part.strip() for part in header.split(",")) if e]
    if len(entries) < hops:
        # Fewer entries than trusted proxies: the header is missing or was not
        # written by our proxies. Fall back to the peer address.
        return peer
    return _valid_ip(entries[-hops]) or peer
