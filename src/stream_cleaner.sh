#!/usr/bin/env bash
#
# Script: stream_cleaner.sh
# Description: Filters media files to keep only specified video, audio, and subtitle
#              streams based on language. No re-encoding is performed (stream copy mode).
# Usage: ./stream_cleaner.sh [OPTIONS]

set -o errexit   # Exit on most errors
set -o nounset   # Disallow expansion of unset variables
set -o pipefail  # Pipeline fails if any command in the pipeline fails

# Constants
readonly INCLUDE_VIDEO_DEFAULT=true
readonly DRY_RUN_DEFAULT=false
readonly VERBOSE_DEFAULT=false

# Global variables
input_file=""
root_dir=""
ext=""
o_ext=""
codec_mode=""
include_video="$INCLUDE_VIDEO_DEFAULT"
dry_run="$DRY_RUN_DEFAULT"
verbose="$VERBOSE_DEFAULT"

# Global arrays
declare -a audio_langs=()
declare -a audio_tracks=()
declare -a sub_langs=()
declare -a files=()
declare -a files_to_process=()
declare -a commands=()
declare -a streams_info=()
declare -a map_args=()
declare -a kept_streams=()

# Logging functions
error() {
  printf "ERROR: %s\n" "$*" >&2
}

info() {
  if [[ "$verbose" == true ]]; then
    printf "[INFO] %s\n" "$*"
  fi
}

log() {
  printf "%s\n" "$*"
}

# Function to display help
usage() {
  cat <<EOF
Usage: $0 [OPTIONS]

Options:
  -i, --input-file <file>       Input media file to process (cannot be used with --root-dir)
  -r, --root-dir <directory>    Root directory containing media files (cannot be used with --input-file)
  -x, --input-ext <extension>   Input ,edia file(s) extension to process (cannot be used with --input-file)
  -o, --output-ext <extension>  Input ,edia file(s) extension to process (cannot be used with --input-file)
  -a, --audio-langs <langs>     Comma-separated list of audio languages to keep (e.g., "jpn,eng")
  -t, --audio-tracks <tracks>   Comma-separated list of audio tracks to keep (e.g., "1,4")
  -s, --sub-langs <langs>       Comma-separated list of subtitle languages to keep (e.g., "eng,deu")
  -n, --no-video                Exclude video streams (include all video by default)
  -d, --dry-run                 Simulate the process without modifying files (shows detailed output)
  -v, --verbose                 Enable verbose output
  -h, --help                    Show this help message
EOF
  exit 0
}

# Parse command-line arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    -i|--input-file)
      if [[ -n "${root_dir}" ]]; then
        error "Cannot use --input-file and --root-dir together."
        exit 1
      fi
      input_file="${2:-}"
      if [[ -z "${input_file}" ]]; then
        error "--input-file requires a file argument."
        exit 1
      fi
      if [[ ! -f "${input_file}" ]]; then
        error "Input file '${input_file}' does not exist or is not a file."
        exit 1
      fi
      shift 2
      ;;
    -r|--root-dir)
      if [[ -n "${input_file}" ]]; then
        error "Cannot use --root-dir and --input-file together."
        exit 1
      fi
      root_dir="${2:-}"
      if [[ -z "${root_dir}" ]]; then
        error "--root-dir requires a directory argument."
        exit 1
      fi
      if [[ ! -d "${root_dir}" ]]; then
        error "Root directory '${root_dir}' does not exist or is not a directory."
        exit 1
      fi
      shift 2
      ;;
    -x|--input-ext)
      if [[ -n "${input_file}" ]]; then
        error "Cannot use --ext and --input-file together."
        exit 1
      fi
      ext="${2:-}"
      if [[ -z "${ext}" ]]; then
        error "Extension cannot be empty"
        exit 1
      fi
      shift 2
      ;;
    -o|--output-ext)
      o_ext="${2:-}"
      if [[ -z "${o_ext}" ]]; then
        error "Output Extension cannot be empty"
        exit 1
      fi
      shift 2
      ;;
    -a|--audio-langs)
      IFS=',' read -ra audio_langs <<< "${2:-}"
      if [[ -n "${audio_tracks[@]}" ]]; then
        error "Cannot use --audio-langs and --audio-tracks together."
        exit 1
      fi
      if [[ ${#audio_langs[@]} -eq 0 ]]; then
        error "--audio-langs requires at least one language."
        exit 1
      fi
      shift 2
      ;;
    -t|--audio-tracks)
      IFS=',' read -ra audio_tracks <<< "${2:-}"
      if [[ -n "${audio_langs[@]}" ]]; then
        error "Cannot use --audio-tracks and --audio-langs together."
        exit 1
      fi
      if [[ ${#audio_tracks[@]} -eq 0 ]]; then
        error "--audio-tracks requires at least one language."
        exit 1
      fi
      shift 2
      ;;
    -s|--sub-langs)
      IFS=',' read -ra sub_langs <<< "${2:-}"
      if [[ ${#sub_langs[@]} -eq 0 ]]; then
        error "--sub-langs requires at least one language."
        exit 1
      fi
      shift 2
      ;;
    -n|--no-video)
      include_video=false
      shift
      ;;
    -d|--dry-run)
      dry_run=true
      shift
      ;;
    -v|--verbose)
      verbose=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      error "Unknown option '$1'"
      usage
      ;;
  esac
done

# Validate that either --input-file or --root-dir is provided
if [[ -z "${input_file}" && -z "${root_dir}" ]]; then
  error "Either --input-file or --root-dir is required."
  usage
fi

if [[ -n "${root_dir}" && -z "${ext}" ]]; then
  ext="mkv"
  log "Using root_dir without extention defaults to mkv"
fi

if [[ -z "${o_ext}" ]]; then
  o_ext="${ext}"
fi

# Store file info for later execution
if [[ "${ext}" == "${o_ext}" ]]; then
  codec_mode="-c copy"
fi

# Check for required tools
for cmd in ffmpeg ffprobe; do
  if ! command -v "${cmd}" &>/dev/null; then
    error "'${cmd}' is required but not installed."
    exit 1
  fi
done

# Populate files array with files to process
populate_files() {
  info "Files to process: "
  if [[ -n "${input_file}" ]]; then
    files=("${input_file}")
  else
    for file in "${root_dir}"/*."${ext}"; do
      if [[ -f "$file" ]]; then
        files+=("${file}")
        info "${file}"
      fi
    done
  fi
}

# Process streams and populate global map_args and kept_streams
process_streams() {
  local stream_type="$1"
  local streams="$2"
  local -n langs="$3"

  for lang in "${langs[@]}"; do
    local indices
    indices=$(awk -v stream_type="${stream_type}" -v lang="${lang}" '
      {
        if ($0 ~ "codec_type=[\047\042]" stream_type "[\047\042]") {
          if (match($0, /streams\.stream\.[0-9]+/)) {
            stream_idx = substr($0, RSTART, RLENGTH)
            split(stream_idx, a, ".")
            current_stream = a[3]
          }
        }
        lower_line = tolower($0)
        lang_lower = tolower(lang)
        if (lower_line ~ "tags\.language=[\047\042]" lang_lower "[\047\042]" ||
            lower_line ~ "language=[\047\042]" lang_lower "[\047\042]") {
          if (match($0, /streams\.stream\.[0-9]+/)) {
            lang_idx = substr($0, RSTART, RLENGTH)
            split(lang_idx, b, ".")
            current_lang = b[3]
          }
        }
        if (current_stream == current_lang && current_stream != "") {
          print current_stream
          current_stream = ""
          current_lang = ""
        }
      }' <<< "${streams}" | sort -h | uniq | tr '\n' ' ')

    if [[ -n "${indices}" ]]; then
      for index in ${indices}; do
        map_args+=("-map" "0:${index}")
        kept_streams+=("${stream_type^} (index: ${index}, language: ${lang})")
      done
    fi
  done
}

# Verify each index is of the expected type using ffprobe flat output,
# then populate global map_args and kept_streams.
# Type mismatches and missing indices are skipped.
process_indices() {
  local stream_type="$1"
  local streams="$2"
  local -n indices="$3"

  for index in "${indices[@]}"; do
    local actual_type
    actual_type=$(awk -v idx="streams.stream.${index}.codec_type" '
      index($0, idx "=") == 1 {
        line = $0
        sub(/^[^=]*=/, "", line)
        gsub(/["\047]/, "", line)
        print line
        exit
      }' <<< "${streams}")

    # Skip silently if index is missing or type does not match.
    if [[ "${actual_type}" == "${stream_type}" ]]; then
      map_args+=("-map" "0:${index}")
      kept_streams+=("${stream_type^} (index: ${index})")
    else
      info "Index ${index} was expected to be of type ${stream_type}, but was found to be of type ${actual_type}"
    fi
  done
}

# Process a single file and gather info
process_file() {
  local input_file="$1"
  local temp_file="${input_file%.${ext}}_clean.${o_ext}"

  # Clear global arrays for this file
  map_args=()
  kept_streams=()

  # Get all streams from ffprobe
  local ffprobe_output
  ffprobe_output=$(ffprobe -v error -show_streams -print_format flat "${input_file}" 2>&1)
  if [[ $? -ne 0 ]]; then
    error "Failed to probe file '${input_file}'."
    return 1
  fi

  # Include all video streams if requested
  if [[ "${include_video}" == true ]]; then
    map_args+="-map 0:v"
  fi

  # Process audio streams
  if [[ -n "${audio_langs[@]}" ]]; then
    process_streams "audio" "${ffprobe_output}" audio_langs
  else
    process_indices "audio" "${ffprobe_output}" audio_tracks
  fi

  # Process subtitle streams
  process_streams "subtitle" "${ffprobe_output}" sub_langs

  # If no streams were selected, skip the file
  if [[ ${#map_args[@]} -eq 0 ]]; then
    info "No matching streams found in '${input_file}'. Skipping."
    return 0
  fi

  # Get the original streams (all indices)
  original_streams=$(awk '
    /streams\.stream\.[0-9]+/ {
      if (match($0, /streams\.stream\.[0-9]+/)) {
        stream_idx = substr($0, RSTART, RLENGTH)
        split(stream_idx, a, ".")
        print a[3]
      }
    }' <<< "${ffprobe_output}" | sort -h | uniq | tr '\n' ' ')

  # Get the desired streams (indices from map_args)
  desired_streams=$(printf "%s\n" "${map_args[@]}" | grep -oE '0:[0-9]+' | cut -d':' -f2 | sort -h | tr '\n' ' ')

  # If the original and desired streams match, skip processing
  if [[ "${original_streams}" == "${desired_streams}" ]]; then
    log "File '${input_file}' already matches desired streams. Skipping."
    return 0
  fi

  commands+=("ffmpeg -i \"${input_file}\" ${map_args[*]} ${codec_mode} -y \"${temp_file}\"")
  files_to_process+=("${input_file}")
  streams_info+=("File: ${input_file}
Streams to KEEP:
$(for stream in "${kept_streams[@]}"; do echo "  ✅ ${stream}"; done)
Command to run:
  ${commands[-1]}")
}

# Gather info for all files
gather_file_info() {
  for input_file in "${files[@]}"; do
    process_file "${input_file}"
  done
}

# Execute commands for all files
execute_commands() {
  for i in "${!commands[@]}"; do
    input_file="${files_to_process[$i]}"
    temp_file="${input_file%.${ext}}_clean.${o_ext}"
    command="${commands[$i]}"

    info "Executing: ${command}"
    if eval "${command}" 2>/dev/null; then
      rm -vrf "${input_file}"
      mv -v "${temp_file}" "${input_file%.${ext}}.${o_ext}"
      log "Success: File ${input_file} updated."
    else
      error "Failed to process file '${input_file}'."
      rm -vf "${temp_file}"
    fi
  done
}

# Main execution
log "Starting media stream filtering..."
if [[ -n "${input_file}" ]]; then
  info "Input file: ${input_file}"
else
  info "Root directory: ${root_dir}"
fi
info "Audio languages to keep: ${audio_langs[*]}"
info "Subtitle languages to keep: ${sub_langs[*]}"
info "Include video streams: ${include_video}"
if [[ -n "${dry_run}" ]]; then
    log "=== DRY RUN ==="
fi
log ""

# Populate files and gather info
populate_files
gather_file_info

# Display summary of what will be done
if [[ ${#commands[@]} -eq 0 ]]; then
  log "No files to process. Exiting."
  exit 0
fi

info "\n=== SUMMARY OF CHANGES ==="
for stream_info in "${streams_info[@]}"; do
  info "${stream_info}\n"
done

# Prompt for confirmation if not in dry-run mode
if [[ "${dry_run}" == false ]]; then
  log "Execute the above commands? [Y/n] "
  read -r reply
  log ""
  if [[ ! "${reply}" =~ ^[Yy]$ && -n "${reply}" ]]; then
    log "Aborted. No files were modified."
    exit 0
  fi

  execute_commands
fi

log "Done."
