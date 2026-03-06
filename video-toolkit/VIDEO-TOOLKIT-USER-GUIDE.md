# Video Publishing with Piwigo Publisher

> **Who this is for**: Lightroom Classic users who want to publish videos to their Piwigo gallery alongside photos.

---

## What You Get

With the standard Piwigo Publisher plugin, **photos publish fine — but videos don't**. To enable video publishing, two optional components work together:

```
Your Lightroom ──────────────────────────────► Your Piwigo Gallery
                                                        ▲
  [Piwigo Publisher plugin]                             │
         │                                              │
         ├── Photos ──────────────────────────── upload directly
         │
         └── Videos ──► [Video Toolkit] ──► compress ──► upload
                              ▲
                    Python + FFmpeg on your computer
```

| Component | Where it lives | What it does |
|-----------|---------------|-------------|
| **Lightroom Companion** | On your Piwigo server | Tells Lightroom "video uploads are allowed here" |
| **Video Toolkit (VTK)** | On your computer | Compresses videos before upload |

Both are **optional but recommended**. Without the Companion, videos are blocked entirely. Without VTK, videos are uploaded as Lightroom renders them — usually fine for small files, risky for large ones.

---

## Before You Start

### On your Piwigo server

1. Install the **Lightroom Companion** plugin (copy the `lightroom_companion/` folder into Piwigo's `plugins/` directory)
2. In Piwigo admin → Plugins → activate **Lightroom Companion**
3. Go to **Plugins → Lightroom Companion** → click **"Enable Video Support"**
4. Install the **VideoJS** plugin from the Piwigo plugin browser — without it, videos won't play in the gallery

### On your computer

Install these three tools (all free):

| Tool | Why you need it | Download |
|------|----------------|---------|
| **Python 3.8+** | Runs the Video Toolkit | [python.org/downloads](https://www.python.org/downloads/) |
| **FFmpeg** | Compresses the video | [ffmpeg.org/download](https://ffmpeg.org/download.html) |
| **ExifTool** *(optional)* | Copies GPS, date, keywords to the compressed file | [exiftool.org](https://exiftool.org/) |

> For platform-specific installation instructions (winget, brew, apt, manual), see [`INSTALL.md`](INSTALL.md).

**Windows shortcut** — open a terminal and run:
```cmd
winget install Python.Python.3
winget install Gyan.FFmpeg
winget install OliverBetz.ExifTool
```

> **Shortcut from Lightroom**: in the publish service settings → Video Settings → Advanced, each tool path has a **Download** button that opens the official page directly.

---

## Setting Up in Lightroom

Open your Piwigo publish service settings (right-click → Edit Settings). Scroll down to **Video Settings**.

```
┌─ Video Settings ──────────────────────────────────┐
│ Video Toolkit                                      │
│   ☑ Include video files in publications            │
│   ☑ Enable Video Toolkit (local transcoding)       │
│                                                    │
│ Encoding Settings                                  │
│   Default preset:  [ Medium (720p) ▼ ]             │
│   Hardware accel:  [ Auto (detect GPU) ▼ ]         │
│   Poster thumbnail: ☑ Generate poster (JPG)        │
│   Poster at: [ 10 ] % of duration                  │
│                                                    │
│ Status                                             │
│   Use 'Check Tools' to verify installation.        │
│   [ Check Tools... ]                               │
│                                                    │
│ Advanced — Tool Paths                              │
│   Python:   C:\Python3\python.exe    [ Download ]  │
│   FFmpeg:   C:\ffmpeg\ffmpeg.exe     [ Download ]  │
│   FFprobe:  C:\ffmpeg\ffprobe.exe    [ Download ]  │
│   ExifTool: C:\exiftool.exe          [ Download ]  │
│   Presets file: (built-in presets)                 │
└────────────────────────────────────────────────────┘
```

**Step by step:**

1. Check **"Include video files in publications"**
2. Check **"Enable Video Toolkit"**
3. Click **"Check Tools…"** — it verifies Python, FFmpeg and ExifTool, and fills in the paths automatically
4. If the check passes, you're ready

---

## Choosing a Quality Preset

The preset controls how much the video is compressed before upload. Pick based on your typical source material and your server's storage capacity.

| Preset | Max size | Typical file | Best for |
|--------|----------|-------------|---------|
| **Small (480p)** | 854×480 | ~30 MB/min | Shared hosting, mobile viewing |
| **Medium (720p)** | 1280×720 | ~90 MB/min | **Good default** for most galleries |
| **Large (1080p)** | 1920×1080 | ~200 MB/min | HD quality, VPS or dedicated server |
| **XLarge (1440p)** | 2560×1440 | ~400 MB/min | 2K sources |
| **XXL (2160p)** | 3840×2160 | ~750 MB/min | 4K archival |
| **Origin** | unchanged | varies | Already web-ready files |

> **Good to know**: if your source is smaller than the preset's maximum, it stays at its original size. A 720p video processed with "Large (1080p)" stays at 720p — it is never upscaled.

> **Origin preset**: the file is uploaded as-is, without any compression. Use it only if the video is already in a web-friendly format (H.264 MP4) and is not too large.

---

## What Happens When You Click "Publish"

```
You click Publish
        │
        ▼
Plugin scans the batch
        │
        ├─ No videos? ──► publish photos normally (done)
        │
        └─ Videos found?
                │
                ▼
        Ask the Piwigo server: "Are video uploads allowed?"
                │
                ├─ No (Companion not installed, or video not enabled)
                │       └──► Videos removed from batch, photos continue
                │             A message tells you which videos were skipped and why
                │
                └─ Yes
                        │
                        ▼
                Video Toolkit compresses each video
                        │
                        ├─ Already compressed recently? ──► skip (uses cache)
                        │
                        └─ New or changed? ──► compress with FFmpeg
                                │
                                ▼
                        Generate poster image (JPG cover)
                                │
                                ▼
                        Upload compressed video + poster to Piwigo
                                │
                                ▼
                        Delete local compressed copy (the original is untouched)
```

**Your original video file is never modified or deleted.**

---

## GPU Acceleration

If you have a compatible GPU (NVIDIA, AMD, Intel), VTK can use it to speed up compression.

| Mode | What it does |
|------|-------------|
| **Auto** *(recommended)* | Detects your GPU and uses it if available; falls back to CPU silently |
| **CPU only** | Always uses the processor — slower but works everywhere |
| **GPU (force)** | Forces GPU; retries with CPU automatically if the GPU fails |

> **Note**: most videos from a camera (SDR H.264) are simply **remuxed** — the video stream is copied as-is with no re-encoding. GPU acceleration only applies when actual encoding is needed (typically HDR footage that must be converted to SDR). For day-to-day use, the GPU setting rarely makes a visible difference.

---

## The Poster Image

The poster is the cover image displayed in your Piwigo gallery before the video plays.

- VTK extracts a frame from the video at a configurable position (default: 10% into the video)
- The Lightroom Companion plugin processes it server-side: resize, optional film-strip border, optional play-button overlay
- You can adjust the frame position with **"Poster at: N % of duration"**

---

## Points to Watch

### Server storage
Videos are large. 10 videos at 100 MB each = 1 GB consumed on your server. Check your hosting plan's disk quota before bulk publishing.

### Shared hosting
If your Piwigo is on shared hosting (OVH, o2switch, etc.):
- Use **Small (480p)** or **Medium (720p)** presets to keep files manageable
- Publish **a few videos at a time** rather than 50 at once
- The plugin handles large files automatically via chunked upload — no manual workaround needed

### VideoJS is required for playback
Without the [VideoJS plugin](https://fr.piwigo.org/ext/index.php?eid=610) on Piwigo, uploaded videos will show as broken or not play. Install it from the Piwigo plugin browser before publishing your first video.

### ExifTool is optional but useful
Without ExifTool, the compressed video will lose its GPS location, capture date, title and keywords. If these matter to you (especially GPS for travel photos/videos), install ExifTool.

### First-time setup
Always click **"Check Tools…"** after installation. It validates everything, fills in the paths, and shows a clear OK or error message. Do not skip this step.

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|-------------|-----|
| Videos skipped silently | Companion not installed or video not enabled | Install Companion, click "Enable Video Support" in its admin page |
| "Check Tools" fails | Python or FFmpeg not found | Install the missing tool, then click Check Tools again — paths are filled automatically |
| Video uploads but won't play | VideoJS not installed | Install VideoJS from Piwigo plugin browser |
| Poster image missing or wrong frame | Poster at % too early/late | Adjust "Poster at" (try 5–20%) |
| Upload very slow | Large file, slow connection | Use a smaller preset; the plugin uses chunked upload automatically for large files |
| GPS / date missing on video | ExifTool not installed | Install ExifTool and click Check Tools again |

---

## Quick Reference Card

```
FIRST TIME:
  Server side  → Install Lightroom Companion → Enable Video Support → Install VideoJS
  Your machine → Install Python + FFmpeg (+ ExifTool) → Check Tools in Lightroom

DAILY USE:
  Include videos in collection → click Publish → done
  (VTK compresses automatically, cache avoids re-compressing unchanged videos)

PRESET CHOICE:
  Shared hosting  → Small (480p)
  Standard use    → Medium (720p)   ← recommended default
  HD gallery      → Large (1080p)
  Already encoded → Origin

IF SOMETHING GOES WRONG:
  Check Tools... → read the message → fix the indicated issue
```
