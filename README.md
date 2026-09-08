# Media File Stream Cleaner

A Bash script to clean media files keeping only specified video, audio, and subtitle streams based on language. No re-encoding is performed (stream copy mode).

---

## Features
- **Filter by Language**: Keep only audio/subtitle streams in specified languages.
- **No Re-encoding**: Uses `ffmpeg` in stream copy mode (`-c copy`) for fast processing.
- **Dry Run Mode**: Preview changes without modifying files.
- **Verbose Output**: Enable detailed logging for debugging.
- **Batch Processing**: Process a single file or all MKV files in a directory.

---

## Requirements
- **Bash** (tested on Bash 5.3.15)
- **[ffmpeg](https://ffmpeg.org/)** (must be in `$PATH`)
- **[ffprobe](https://ffmpeg.org/ffprobe.html)** (included with `ffmpeg`)

---

## Installation
1. Clone or download the script:
   ```bash
   git clone https://github.com/vr-ski/stream-cleaner.git
   cd stream-cleaner/src
   ```
2. Make the script executable:
   ```bash
   chmod +x stream_cleaner.sh
   ```

---

## Usage
```bash
./stream_cleaner.sh [OPTIONS]
```

### Options
| Option               | Description                                                                 |
|----------------------|-----------------------------------------------------------------------------|
| `-i, --input-file`   | Input MKV file to process (cannot be used with `--root-dir`).              |
| `-r, --root-dir`     | Root directory containing MKV files (cannot be used with `--input-file`). |
| `-a, --audio-langs`  | Comma-separated list of audio languages to keep (e.g., `"jpn,eng"`).       |
| `-s, --sub-langs`    | Comma-separated list of subtitle languages to keep (e.g., `"eng,deu"`).   |
| `-n, --no-video`     | Exclude video streams (include all video by default).                    |
| `-d, --dry-run`      | Simulate the process without modifying files (shows detailed output).    |
| `-v, --verbose`      | Enable verbose output.                                                     |
| `-h, --help`         | Show this help message.                                                    |

---

## Examples
### Process a Single File
Keep only Japanese audio and English subtitles in `movie.mkv`:
```bash
./stream_cleaner.sh --input-file movie.mkv --audio-langs jpn --sub-langs eng
```

### Process All MKV Files in a Directory
Keep only Japanese audio and English/German subtitles in all MKV files in `/path/to/files`:
```bash
./stream_cleaner.sh --root-dir /path/to/files --audio-langs jpn --sub-langs eng,deu
```

### Dry Run (Preview Changes)
Preview what would happen without modifying files:
```bash
./stream_cleaner.sh --input-file movie.mkv --audio-langs jpn --sub-langs eng --dry-run
```

### Exclude Video Streams
Keep only Japanese audio and English subtitles, excluding video:
```bash
./stream_cleaner.sh --input-file movie.mkv --audio-langs jpn --sub-langs eng --no-video
```

---

## License
This project is licensed under the **BSD-2-Clause License** – see the [LICENSE](LICENSE) file for details.

---
