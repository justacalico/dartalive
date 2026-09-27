# DartAlive

A free, open-source non-linear video editor for Linux, Windows and macOS.
Timeline editing, nested sequences, dockable panels, color grading, effects,
keyframes, FFmpeg-powered preview and export.

Projects are saved as `.dal` files (ZIP archives). Media is referenced relative
to the project file, so a project on removable media stays portable.

## Features

- Multi-track timeline with snapping, ripple edits, transitions and keyframes
- Nested sequences: edit a sequence, drop it into another timeline like a clip
- Dockable, resizable panels with saved layouts
- Effects and color grading: transform, crop, EQ, levels, curves, LUTs, channel
  mixer, blur, sharpen, chroma key, vignette and more
- Audio: gain, pan, fades, EQ, compressor, loudness normalization, mixer
- Real-time preview rendered by an FFmpeg frame server with frame caching,
  proxy media and adjustable preview resolution
- Export and transcode: H.264, HEVC, VP9, ProRes, DNxHD, render queue
- Imports Kdenlive projects (.kdenlive)
- Configurable keyboard shortcuts

## Requirements

- `ffmpeg` and `ffprobe` on PATH (or configured in Settings)
- Flutter 3.44+ to build from source

## License

AGPL-3.0. See LICENSE.
