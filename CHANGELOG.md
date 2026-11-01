# Changelog

## Unreleased

### Added

- Added classic click-and-hold canvas navigation: the ship continuously retargets toward the held pointer at a throttled cadence, including while the camera moves beneath a stationary cursor.
- Added pointer-capture lifecycle handling for release, cancellation, lost capture, window blur, and document visibility changes.
- Added focused JavaScript tests for click navigation, throttling, camera-aware retargeting, redundant-command suppression, the near-ship dead zone, and cancellation safety.

### Preserved

- Movement remains server-authoritative: the browser sends destinations only, while the world simulation continues to validate map boundaries and own ship positions and speeds.
