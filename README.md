# fcfile

The first five minutes of every CTF forensics challenge are the same: `file`, `exiftool`, `strings`, `binwalk`, squint at the hex. I got tired of typing it, so this does all of that at once and then runs whatever makes sense for the file type.

```
$ ./fcfile.sh -p wicys mystery.png
!! 20 bytes after IEND. something is appended: tail -c 20 "mystery.png" > after_iend.bin
>>> wicys{after_the_end}
```

## Usage

```
./fcfile.sh file.png                     # one file
./fcfile.sh *.jpg                        # a bunch at once
./fcfile.sh -p picoCTF file.bin          # only hunt picoCTF{...}
./fcfile.sh -w rockyou.txt photo.jpg     # run stegseek with a wordlist
./fcfile.sh -x firmware.bin              # also extract with binwalk -e and foremost
./fcfile.sh -o report.txt evidence/*     # save everything to a file
```

`NO_COLOR=1` turns the colors off.

## What it checks

Every file gets the basics plus a flag hunt through ASCII strings, UTF-16 strings, and any base64 hiding in them. It also yells if the extension doesn't match the magic bytes, because a `.txt` that's secretly a PNG shows up more often than you'd think.

After that it depends on the type:

| Type | What runs |
|---|---|
| PNG / BMP | pngcheck, zsteg, and a count of bytes after `IEND` |
| JPEG / WAV | steghide with a blank password, stegseek if you gave a wordlist |
| GIF | frame count and delays |
| pcap | capinfos, protocol breakdown, HTTP requests, DNS queries |
| ELF | checksec |
| Windows exe | spots .NET, PyInstaller, and pyarmor |
| zip / 7z / rar | lists what's inside, plus the john command if it's locked |
| Office docs | olevba for macros |
| PDF | pdfinfo, the text, and a warning if there's JavaScript or embedded files |

If a tool isn't installed it says so and moves on. On a bare box you still get the basics, and on Kali you get pretty much everything.

It only reads files, with two exceptions: `-x` writes extracted files next to the original, and if the blank-password steghide try works, it saves `<file>.steghide.out`.

## fcgen.sh

Same detection, but it just prints the commands so you can run them one at a time. Good for when you want to see each step instead of a wall of output.

```
bash fcgen.sh
```

## Installing the optional tools

Only `file`, `strings`, and `xxd` (or `od`) are required. For the rest on Debian or Ubuntu:

```
sudo apt install exiftool binwalk foremost pngcheck steghide imagemagick tshark checksec p7zip-full poppler-utils
gem install zsteg
pip install oletools
```
