#!/bin/bash
# fcfile - run first-contact recon on a file, then type-specific recon
# usage:  fcfile [options] <file> [more files...]
#   -p PREFIX   flag prefix to hunt for (eg wicys). default: anything{...}
#   -w LIST     wordlist for stegseek on jpg/wav (eg rockyou.txt)
#   -x          also extract embedded stuff (binwalk -e / foremost). writes files!
#   -o FILE     save the whole report to FILE too
#   -h          help

prefix=""
wl=""
extract=0
out=""

usage() { sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0; }

while getopts "p:w:xo:h" o; do
  case "$o" in
    p) prefix="$OPTARG" ;;
    w) wl="$OPTARG" ;;
    x) extract=1 ;;
    o) out="$OPTARG" ;;
    h|*) usage ;;
  esac
done
shift $((OPTIND - 1))

# colors, unless piped or NO_COLOR is set
if [ -t 1 ] && [ -z "$NO_COLOR" ] && [ -z "$out" ]; then
  B=$'\e[1;35m'; G=$'\e[1;32m'; Y=$'\e[1;33m'; D=$'\e[2m'; N=$'\e[0m'
else
  B=""; G=""; Y=""; D=""; N=""
fi

if [ -n "$prefix" ]; then
  pat="${prefix}\{[^}]+\}"
else
  pat="[A-Za-z0-9_]{2,}\{[^}]{3,}\}"
fi

# small helper so we dont choke on a tool thats not installed
run() {
  if command -v "$1" >/dev/null 2>&1; then
    echo; echo "${B}== $* ==${N}"
    "$@" 2>&1
  else
    echo; echo "${D}== $1 (not installed, skipping) ==${N}"
  fi
}

# what extension should this magic be? used for the mismatch check
want_ext() {
  case "$1" in
    *PNG*) echo "png" ;;
    *JPEG*) echo "jpg jpeg" ;;
    *GIF*) echo "gif" ;;
    *PDF*) echo "pdf" ;;
    *"Zip archive"*) echo "zip docx xlsx pptx jar apk odt" ;;
    *gzip*) echo "gz tgz" ;;
    *"RAR archive"*) echo "rar" ;;
    *"7-zip"*) echo "7z" ;;
    *ELF*) echo "elf so o bin" ;;
    *PE32*) echo "exe dll sys" ;;
    *WAVE*) echo "wav" ;;
    *pcapng*|*"pcap capture"*|*tcpdump*) echo "pcap pcapng cap" ;;
    *) echo "" ;;
  esac
}

triage() {
  f="$1"
  if [ ! -f "$f" ]; then
    echo "cant find: $f"
    echo "(wrong folder? cd to where the file actually is)"
    return 1
  fi

  t=$(file -b "$f")
  ext=$(echo "${f##*.}" | tr 'A-Z' 'a-z')
  [ "$ext" = "$(echo "$f" | tr 'A-Z' 'a-z')" ] && ext=""  # no extension at all

  echo "${B}############################################${N}"
  echo "${B}# first contact: $f${N}"
  echo "${B}# detected: $t${N}"
  echo "${B}# size: $(wc -c < "$f") bytes${N}"
  echo "${B}############################################${N}"

  # extension lying about what the file is? classic
  w=$(want_ext "$t")
  if [ -n "$w" ] && [ -n "$ext" ] && ! echo " $w " | grep -q " $ext "; then
    echo "${Y}!! extension says .$ext but the magic bytes say: $t${N}"
    echo "${Y}!! try renaming it to .$(echo $w | cut -d' ' -f1)${N}"
  fi
  if echo "$t" | grep -q '^data$'; then
    echo "${Y}!! file doesnt recognize it. corrupted or missing magic bytes? compare the header below to a real one${N}"
  fi

  # --- flag hunt first, sometimes its just sitting there ---
  echo; echo "${B}== flag hunt (ascii + utf-16) ==${N}"
  hits=$( { strings -a -n 6 "$f"; strings -a -n 6 -e l "$f" 2>/dev/null; } | grep -oE "$pat" | sort -u)
  if [ -n "$hits" ]; then
    echo "$hits" | while read -r h; do echo "${G}>>> $h${N}"; done
  else
    echo "${D}nothing flag-shaped in the plain strings${N}"
  fi
  b64=$(strings -a -n 16 "$f" | grep -oE '[A-Za-z0-9+/]{16,}={0,2}' | head -200)
  if [ -n "$b64" ]; then
    echo "$b64" | while read -r s; do
      d=$(echo "$s" | base64 -d 2>/dev/null | tr -d '\0' | grep -oE "$pat")
      [ -n "$d" ] && echo "${G}>>> $d   ${D}(base64 in strings: ${s:0:30}...)${N}"
    done
  fi

  # --- always: the recon core ---
  run exiftool "$f"
  echo; echo "${B}== strings (first 50) ==${N}"; strings -a -n 8 "$f" | head -50
  run binwalk "$f"
  # xxd for the hex view, fall back to od if its missing
  if command -v xxd >/dev/null 2>&1; then
    echo; echo "${B}== header (xxd head) ==${N}"; xxd "$f" | head
    echo; echo "${B}== tail (appended data hides here) ==${N}"; xxd "$f" | tail
  else
    echo; echo "${B}== header (od head) ==${N}"; od -A x -t x1z "$f" | head
    echo; echo "${B}== tail (od) ==${N}"; od -A x -t x1z "$f" | tail
  fi

  # --- type specific, read-only stuff we can safely auto-run ---

  if echo "$t" | grep -qiE 'PNG|bitmap|BMP' || [ "$ext" = "png" ] || [ "$ext" = "bmp" ]; then
    run pngcheck -v "$f"
    run zsteg -a "$f"
    # png with data after IEND
    if grep -aobq 'IEND' "$f"; then
      e=$(grep -aob 'IEND' "$f" | tail -1 | cut -d: -f1)
      sz=$(wc -c < "$f")
      extra=$((sz - e - 8))
      [ "$extra" -gt 0 ] && echo "${Y}!! $extra bytes after IEND. something is appended: tail -c $extra \"$f\" > after_iend.bin${N}"
    fi
  fi

  if echo "$t" | grep -qiE 'JPEG|WAVE|audio' || [ "$ext" = "jpg" ] || [ "$ext" = "jpeg" ] || [ "$ext" = "wav" ]; then
    # try a blank passphrase so it doesnt hang waiting for input
    if command -v steghide >/dev/null 2>&1; then
      echo; echo "${B}== steghide (blank pass) ==${N}"
      steghide extract -sf "$f" -p "" -xf "${f}.steghide.out" -f 2>&1
    fi
    if [ -n "$wl" ]; then
      run stegseek "$f" "$wl"
    else
      echo "${D}# got a wordlist? fcfile -w rockyou.txt \"$f\" runs stegseek${N}"
    fi
    echo "${D}# if that failed: open in Audacity / Sonic Visualiser, check the SPECTROGRAM${N}"
  fi

  if echo "$t" | grep -qiE 'GIF' || [ "$ext" = "gif" ]; then
    if command -v identify >/dev/null 2>&1; then
      echo; echo "${B}== gif frames ==${N}"
      identify -format "%s: %wx%h delay %T\n" "$f" 2>&1 | head -40
      echo "${D}# split them: convert \"$f\" frame_%03d.png${N}"
    fi
  fi

  if echo "$t" | grep -qiE 'pcap|tcpdump|capture' || [ "$ext" = "pcap" ] || [ "$ext" = "pcapng" ]; then
    run capinfos "$f"
    run tshark -r "$f" -q -z io,phs
    run tshark -r "$f" -Y http.request -T fields -e ip.src -e http.host -e http.request.uri
    run tshark -r "$f" -Y dns.qry.name -T fields -e dns.qry.name
    echo "${D}# pull files out: tshark -r \"$f\" --export-objects http,./objs${N}"
    echo "${D}# usb keyboard? tshark -r \"$f\" -T fields -e usbhid.data${N}"
  fi

  if echo "$t" | grep -qiE 'ELF'; then
    run checksec --file="$f"
    echo "${D}# next: load it in ghidra to decompile${N}"
  fi

  if echo "$t" | grep -qiE 'PE32|MS Windows'; then
    if echo "$t" | grep -qi 'Mono/.Net'; then
      echo "${Y}!! .NET assembly. dnSpy / ILSpy will give you near-source${N}"
    fi
    if strings -a "$f" | grep -q 'pyi-\|PyInstaller\|_MEIPASS'; then
      echo "${Y}!! looks like PyInstaller. pyinstxtractor then decompile the .pyc${N}"
    fi
    if strings -a "$f" | grep -q '__pyarmor__'; then
      echo "${Y}!! pyarmor protected. try pyarmor-1shot${N}"
    fi
    echo "${D}# windows exe -> ghidra${N}"
  fi

  if echo "$t" | grep -qiE 'Zip archive|compressed|archive' || echo "$ext" | grep -qE '^(zip|docx|xlsx|pptx|jar|apk|7z|rar|gz|tgz)$'; then
    run unzip -l "$f"
    run 7z l "$f"
    echo "${D}# locked? zip2john \"$f\" > h.txt; john --wordlist=/usr/share/wordlists/rockyou.txt h.txt${N}"
    if echo "$ext" | grep -qE '^(docx|xlsx|pptx|docm|xlsm)$'; then
      run olevba "$f"
      echo "${D}# office docs are zips: unzip it and grep through word/ xl/ etc${N}"
    fi
  fi

  if echo "$t" | grep -qiE 'Composite Document|CDF V2' ; then
    run olevba "$f"
  fi

  # appended zip inside another file (eg png) - unzip reads from the end anyway
  if echo "$f" | grep -qiE '\.(png|jpg|jpeg|gif|bmp)$' && grep -aq 'PK' "$f"; then
    echo; echo "${Y}== looks like an archive is appended ==${N}"
    echo "${D}# try: binwalk -e \"$f\"   or   unzip \"$f\"${N}"
  fi

  if echo "$t" | grep -qiE 'PDF' || [ "$ext" = "pdf" ]; then
    run pdfinfo "$f"
    if command -v pdftotext >/dev/null 2>&1; then
      echo; echo "${B}== pdf text (first 30 lines) ==${N}"; pdftotext "$f" - 2>/dev/null | head -30
    fi
    grep -aqE '/JavaScript|/JS|/OpenAction|/EmbeddedFile' "$f" && echo "${Y}!! pdf has javascript, auto-actions, or embedded files. look closer (pdf-parser / peepdf)${N}"
    echo "${D}# more: pdfimages -all \"$f\" img${N}"
  fi

  # --- opt in: actually extract stuff ---
  if [ "$extract" = 1 ]; then
    run binwalk -e -C "${f}.extracted" "$f"
    if command -v foremost >/dev/null 2>&1; then
      echo; echo "${B}== foremost ==${N}"
      foremost -q -i "$f" -o "${f}.foremost" 2>&1 && ls -R "${f}.foremost" | head -30
    fi
  fi

  echo; echo "${B}############ done: $f ############${N}"
}

if [ $# -eq 0 ]; then
  read -p "file name? " f
  set -- "$f"
fi

if [ -n "$out" ]; then
  for f in "$@"; do triage "$f"; echo; done 2>&1 | tee "$out"
  echo "report saved to $out"
else
  for f in "$@"; do triage "$f"; echo; done
fi
