# Video Toolkit — Installation

## Dependencies

### Required

- **Python** 3.8+
- **FFmpeg** 5.0+ (video transcoding + analysis via ffprobe)

### Optional

- **ExifTool** 12+ (metadata copying — without it, GPS, date and keywords are not copied to the compressed file)

## Installation by Platform

### Windows

#### Via winget (recommended — built into Windows 11)
```cmd
winget install Python.Python.3
winget install Gyan.FFmpeg
winget install OliverBetz.ExifTool
```

#### Via Chocolatey
```cmd
choco install python ffmpeg exiftool
```

#### Manual
1. Download FFmpeg: https://ffmpeg.org/download.html
   - Extract the ZIP to `C:\ffmpeg\`
   - Add `C:\ffmpeg\bin` to the PATH environment variable (or configure the path in Lightroom's Advanced settings)

2. Download ExifTool: https://exiftool.org/
   - Place `exiftool.exe` in `C:\exiftool\` (or any folder that is in PATH)

### macOS

```bash
brew install python@3.11
brew install ffmpeg
brew install exiftool
```

### Linux (Debian / Ubuntu)

```bash
sudo apt update
sudo apt install python3 ffmpeg libimage-exiftool-perl
```

### Linux (Fedora / RHEL)

```bash
sudo dnf install python3 ffmpeg perl-Image-ExifTool
```

### Linux (Arch)

```bash
sudo pacman -S python ffmpeg perl-image-exiftool
```

## Configuring the Toolkit

### Option 1: Auto-detection (recommended)

Tools are detected automatically if they are:
- In the system PATH
- Or at common installation locations (Windows: `C:\ffmpeg\bin\ffmpeg.exe`, etc.)

**From Lightroom**: open the publish service settings → Video Settings → click **"Check Tools…"**. This validates all tools, fills in the path fields automatically, and shows a clear result.

**From the command line**, run the interactive menu to check tool status:
```bash
cd video-toolkit
python video_toolkit.py
# Tools menu shows the status of each dependency
```

### Option 2: Configure manually

If auto-detection fails, set the paths directly in Lightroom under **Video Settings → Advanced — Tool Paths**.

Alternatively, edit `~/.piwigoPublish/video-toolkit.json`:

```json
{
  "ffmpeg_path": "C:\\Program Files\\ffmpeg\\bin\\ffmpeg.exe",
  "ffprobe_path": "C:\\Program Files\\ffmpeg\\bin\\ffprobe.exe",
  "exiftool_path": "C:\\exiftool\\exiftool.exe"
}
```

## Verification

```bash
python video_toolkit.py --mode probe --input sample_video.mp4
```

Should return a JSON object with resolution, duration, codecs, etc.

```bash
python video_toolkit.py
# Interactive menu → Tools (option 3) to check dependency status
```
