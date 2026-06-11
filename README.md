# KanjiIME

KanjiIME is a Rime-based English-to-CJK/Japanese input method bundle.

Type an English meaning and choose a candidate by number or click/tap:

- `fire` -> `火`, `炎`, `火事`
- `water` -> `水`, `水道`, `河`
- `love` -> `愛`, `爱`, `戀`

The same dictionary format powers three modes:

- `kanji_en_jp` - Japanese-oriented output
- `kanji_en_zh` - Simplified Chinese output
- `kanji_en_hk` - Traditional Chinese / Hong Kong output

Pressing `Enter` commits the English text itself. KanjiIME also maps `Space` to `Enter` while composing, so `fire` + `Space` commits `fire`; select translated candidates with number keys or by clicking/tapping them.

Switch modes in Weasel with the Rime schema menu, usually `Ctrl+`` or `F4`, or use:

- `Ctrl+1` - Japanese
- `Ctrl+2` - Simplified Chinese
- `Ctrl+3` - Traditional Chinese / Hong Kong

## Repository Layout

```text
rime/                  Rime schemas and dictionaries
tools/                 Dictionary import/merge tools
scripts/               Windows and Android package builders
packaging/windows/     Windows installer helper files
```

## Dictionary Format

Local source dictionaries are TSV files:

```text
mode<TAB>english<TAB>candidate<TAB>weight<TAB>comment
jp<TAB>fire<TAB>火<TAB>100<TAB>hi
zh<TAB>fire<TAB>火<TAB>100<TAB>huo
hk<TAB>fire<TAB>火<TAB>100<TAB>fo
```

Use `mode` values `jp`, `zh`, `hk`, or `all`.

Rebuild Rime dictionaries after editing `data/seed.tsv` or adding more TSV files:

```powershell
pwsh ./tools/Build-Dictionaries.ps1
```

Import an online TSV dictionary:

```powershell
pwsh ./tools/Import-Dictionary.ps1 -Url "https://example.com/kanjiime.tsv" -OutFile data/external/example.tsv
pwsh ./tools/Build-Dictionaries.ps1
```

## Build Windows EXE

KanjiIME uses Rime Weasel on Windows. The packaging script creates a self-extracting installer EXE that:

1. installs the official Weasel runtime silently when it is missing;
2. copies KanjiIME Rime schemas to `%AppData%\Rime`;
3. sets `kanji_en_jp` as the first/default mode;
4. registers the Windows input profile with `WeaselSetup.exe /s`;
5. deploys only the KanjiIME JP/ZH/HK schema list.

The installer UI is a small English KanjiIME dialog. It does not use the legacy IExpress prompt shell.
It requests administrator permission because Windows input method registration is system-level.

```powershell
pwsh ./scripts/Build-WindowsExe.ps1
```

Output:

```text
dist/windows/KanjiIME-Windows-Setup-*.exe
```

The Windows setup writes a log to `%TEMP%\KanjiIME-Setup.log`.

## Build Android APK

KanjiIME uses Trime on Android. The packaging script clones Trime, copies the KanjiIME Rime assets into its Android assets, and runs Gradle.

```powershell
pwsh ./scripts/Build-AndroidApk.ps1
```

Output:

```text
dist/android/*.apk
```

You need a JDK and Android SDK available for the Trime Gradle build.

If you do not have the Android SDK installed yet, create a practical APK by patching the official Trime release APK with KanjiIME dictionaries:

```powershell
pwsh ./scripts/Build-AndroidPatchedApk.ps1 -Abi arm64-v8a
```

Output:

```text
dist/android/KanjiIME-Trime-*-patched.apk
```

Use `-Abi armeabi-v7a`, `-Abi x86`, or `-Abi x86_64` for other Android CPU architectures.

## Sources

KanjiIME is built on:

- Rime engine: https://rime.im
- Weasel for Windows: https://github.com/rime/weasel
- Trime for Android: https://github.com/osfans/trime
