#!/bin/bash
# fcgen - ask for a file, detect its type, print a copy-paste block tailored to it
# run with:  bash fcgen.sh

read -p "file name? " f   # the target file

# bail if it isnt there
if [ ! -f "$f" ]; then
  echo "cant find: $f"
  echo "(wrong folder? cd to where the file actually is)"
  exit 1
fi

t=$(file -b "$f")                      # brief type description
ext=$(echo "${f##*.}" | tr 'A-Z' 'a-z')   # lowercased extension
# echo "debug: ext=$ext"               # prob dont need

echo
echo "detected: $t"
echo
echo "== copy paste this =="
echo "----------------------------------------"
echo "FILE=\"$f\""
# first contact, always run these
echo 'file "$FILE"; exiftool "$FILE"; strings -n 8 "$FILE" | head -50; binwalk "$FILE"; xxd "$FILE" | head'

# --- category specific follow up, based on what file/ext says ---

# png / bmp -> lsb stego
if echo "$t" | grep -qiE 'PNG|bitmap|BMP' || [ "$ext" = "png" ] || [ "$ext" = "bmp" ]; then
  echo 'zsteg -a "$FILE"   # lsb stego'
fi

# jpg -> steghide
if echo "$t" | grep -qiE 'JPEG' || [ "$ext" = "jpg" ] || [ "$ext" = "jpeg" ]; then
  echo 'steghide extract -sf "$FILE"   # try a blank password first'
fi

# audio -> steghide (wav) + spectrogram
if echo "$t" | grep -qiE 'WAVE|audio' || [ "$ext" = "wav" ] || [ "$ext" = "mp3" ]; then
  echo 'steghide extract -sf "$FILE"'
  echo '# open in Audacity / Sonic Visualiser, check the SPECTROGRAM view'
fi

# pcap -> wireshark / tshark
if echo "$t" | grep -qiE 'pcap|tcpdump|capture' || [ "$ext" = "pcap" ] || [ "$ext" = "pcapng" ]; then
  echo 'tshark -r "$FILE" -Y http   # or open in wireshark, Follow Stream'
  echo 'tshark -r "$FILE" --export-objects http,./out'
fi

# linux binary -> pwn / rev
if echo "$t" | grep -qiE 'ELF'; then
  echo 'checksec "$FILE"   # then load it in ghidra to decompile'
fi

# windows binary -> rev
if echo "$t" | grep -qiE 'PE32|MS Windows'; then
  echo '# windows exe -> ghidra, or dnSpy if its .NET'
fi

# zip / archive -> list + crack hint
if echo "$t" | grep -qiE 'Zip archive|compressed|archive' || [ "$ext" = "zip" ]; then
  echo 'unzip -l "$FILE"   # locked? zip2john "$FILE" > h.txt; john h.txt'
fi

# pdf -> metadata + extract text/images
if echo "$t" | grep -qiE 'PDF' || [ "$ext" = "pdf" ]; then
  echo 'pdfinfo "$FILE"; pdftotext "$FILE" -; pdfimages -all "$FILE" img'
fi

echo "----------------------------------------"
