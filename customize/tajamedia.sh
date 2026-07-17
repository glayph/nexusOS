#!/bin/bash
# ============================================================
#  TajaMedia — Media & Utility Tools
#  Media tagging, conversion, screen recording, OCR, QR, bench
# ============================================================
set -euo pipefail

C='\033[96m'; G='\033[92m'; Y='\033[93m'; R='\033[91m'; N='\033[0m'
log()  { echo -e "${C}[TajaMedia]${N} $*"; }
ok()   { echo -e "${G}[  OK ]${N} $*"; }
die()  { echo -e "${R}[FAIL ]${N} $*"; exit 1; }

# Media tagging
media_tag_audio() { exiftool -Artist="$2" -Title="$3" -Album="$4" "$1" 2>/dev/null || mid3v2 -a "$2" -t "$3" -A "$4" "$1"; }
media_tag_video() { exiftool -Artist="$2" -Title="$3" "$1" 2>/dev/null; }
media_tag_view() { exiftool "$1" 2>/dev/null || ffprobe "$1" 2>/dev/null; }

# Media conversion
media_convert_image() {
  local input="$1" output="$2"
  convert "$input" "$output" 2>/dev/null || ffmpeg -i "$input" "$output" -y
  ok "Converted: $input -> $output"
}

media_convert_audio() {
  local input="$1" output="$2" format="${3:-mp3}"
  ffmpeg -i "$input" -f "$format" "$output" -y
  ok "Converted: $input -> $output"
}

media_convert_video() {
  local input="$1" output="$2" codec="${3:-libx264}"
  ffmpeg -i "$input" -c:v "$codec" -preset fast "$output" -y
  ok "Converted: $input -> $output"
}

media_compress_image() {
  local input="$1" quality="${2:-80}"
  local output="${input%.*}.jpg"
  convert "$input" -quality "$quality" "$output"
  ok "Compressed: $input -> $output ($quality%)"
}

# Screen recording
media_screen_record() {
  local output="${1:-/tmp/recording-$(date +%s).mp4}"
  local fps="${2:-15}"
  local resolution="${3:-1920x1080}"
  ffmpeg -f x11grab -s "$resolution" -r "$fps" -i :0.0 -c:v libx264 -preset ultrafast "$output" -y &
  local pid=$!
  echo "$pid" > /tmp/screenrec.pid
  ok "Recording started (PID: $pid). Stop with: tajamedia screen-stop"
}

media_screen_stop() {
  [[ -f /tmp/screenrec.pid ]] && kill "$(cat /tmp/screenrec.pid)" 2>/dev/null && rm -f /tmp/screenrec.pid && ok "Recording stopped" || warn "No recording running"
}

# OCR
media_ocr() {
  local image="$1"
  tesseract "$image" stdout 2>/dev/null
}

media_ocr_pdf() {
  local pdf="$1"
  ocrmypdf "$pdf" "${pdf%.*}-ocr.pdf" 2>/dev/null
}

# QR Code
media_qr_encode() {
  local data="$1" output="${2:-qr.png}"
  qrencode -o "$output" "$data"
  ok "QR code: $output"
}

media_qr_decode() {
  local image="$1"
  zbarimg "$image" 2>/dev/null
}

# Benchmark
media_bench_cpu() {
  log "CPU benchmark (sysbench)..."
  sysbench cpu run 2>/dev/null | grep -E 'total time|events|per second'
}

media_bench_mem() {
  log "Memory benchmark..."
  sysbench memory run 2>/dev/null | grep -E 'total|transferred|operations'
}

media_bench_disk() {
  log "Disk benchmark..."
  local tmp="/tmp/bench-$$"
  dd if=/dev/zero of="$tmp" bs=1M count=1024 conv=fdatasync 2>&1 | tail -3
  dd if="$tmp" of=/dev/null bs=1M 2>&1 | tail -3
  rm -f "$tmp"
}

media_bench_all() {
  media_bench_cpu
  echo ""
  media_bench_mem
  echo ""
  media_bench_disk
}

usage() {
  cat << USAGE
Usage: tajamedia <command> [args]

Tags:
  tag-audio <file> <artist> <title> [album]
  tag-video <file> <artist> <title>
  tag-view <file>

Convert:
  img <input> <output>            Convert image
  audio <input> <output> [fmt]    Convert audio
  video <input> <output> [codec]  Convert video
  compress <image> [quality]      Compress image (1-100)

Screen Rec:
  record [file] [fps] [res]      Start recording
  stop                           Stop recording

OCR:
  ocr <image>                     OCR image
  ocr-pdf <pdf>                   OCR PDF

QR:
  qr-encode <data> [output]      Generate QR
  qr-decode <image>              Decode QR

Benchmark:
  bench-cpu                       CPU benchmark
  bench-mem                       Memory benchmark
  bench-disk                      Disk benchmark
  bench-all                       All benchmarks
USAGE
}

main() {
  [[ $# -eq 0 ]] && { usage; exit 1; }
  local cmd="$1"; shift
  case "$cmd" in
    tag-audio) media_tag_audio "$@" ;;
    tag-video) media_tag_video "$@" ;;
    tag-view) media_tag_view "$@" ;;
    img) media_convert_image "$@" ;;
    audio) media_convert_audio "$@" ;;
    video) media_convert_video "$@" ;;
    compress) media_compress_image "$@" ;;
    record) media_screen_record "$@" ;;
    stop) media_screen_stop ;;
    ocr) media_ocr "$@" ;;
    ocr-pdf) media_ocr_pdf "$@" ;;
    qr-encode) media_qr_encode "$@" ;;
    qr-decode) media_qr_decode "$@" ;;
    bench-cpu) media_bench_cpu ;;
    bench-mem) media_bench_mem ;;
    bench-disk) media_bench_disk ;;
    bench-all) media_bench_all ;;
    *) usage; exit 1 ;;
  esac
}

main "$@"