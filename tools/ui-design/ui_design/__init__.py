"""Public design review interface; product policy and files are caller-owned."""

from .engine import check, snapshot

__all__ = ['check', 'snapshot']
