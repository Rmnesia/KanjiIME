from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / "assets"
W, H = 820, 360


def font(path, size):
    return ImageFont.truetype(str(path), size)


FONT_UI = Path("C:/Windows/Fonts/segoeui.ttf")
FONT_UI_BOLD = Path("C:/Windows/Fonts/segoeuib.ttf")
FONT_JP = Path("C:/Windows/Fonts/NotoSansJP-VF.ttf")
FONT_SC = Path("C:/Windows/Fonts/NotoSansSC-VF.ttf")
FONT_TC = Path("C:/Windows/Fonts/NotoSansTC-VF.ttf")


def rounded(draw, box, radius, fill, outline=None, width=1):
    draw.rounded_rectangle(box, radius=radius, fill=fill, outline=outline, width=width)


def text(draw, xy, value, fill, size=18, bold=False, cjk=False, mode="jp"):
    if cjk:
        face = {"jp": FONT_JP, "zh": FONT_SC, "hk": FONT_TC}[mode]
    else:
        face = FONT_UI_BOLD if bold else FONT_UI
    draw.text(xy, value, fill=fill, font=font(face, size))


def centered_text(draw, box, value, fill, size=14, bold=False):
    face = FONT_UI_BOLD if bold else FONT_UI
    f = font(face, size)
    bbox = draw.textbbox((0, 0), value, font=f)
    x = box[0] + (box[2] - box[0] - (bbox[2] - bbox[0])) / 2
    y = box[1] + (box[3] - box[1] - (bbox[3] - bbox[1])) / 2 - 1
    draw.text((x, y), value, fill=fill, font=f)


def make_frame(mode, typed, candidates=None, committed=None, active="jp"):
    img = Image.new("RGB", (W, H), "#f7f9fc")
    draw = ImageDraw.Draw(img)

    text(draw, (42, 34), "KanjiIME", "#172033", 28)
    text(draw, (42, 72), "Type English meaning. Pick kanji or hanzi with readings.", "#58677d", 17)

    tabs = [
        ("jp", "JP", "Japanese"),
        ("zh", "ZH", "Simplified"),
        ("hk", "HK", "Traditional"),
    ]
    x = 42
    for key, label, name in tabs:
        is_active = key == active
        width = 110 if key == "jp" else 114 if key == "zh" else 118
        fill = "#2563eb" if is_active else "#eef3f9"
        fg = "#ffffff" if is_active else "#526074"
        rounded(draw, (x, 108, x + width, 142), 8, fill)
        text(draw, (x + 14, 119), label, fg, 13, bold=is_active)
        text(draw, (x + 40, 119), name, fg, 13)
        x += width + 8

    rounded(draw, (42, 158, 778, 303), 8, "#ffffff", "#cbd7e6")
    text(draw, (66, 185), "Input", "#64748b", 14)
    text(draw, (66, 213), typed + ("|" if committed is None else ""), "#172033", 30, cjk=False)

    if candidates:
        cx, cy = 66, 246
        for i, cand in enumerate(candidates, 1):
            word, reading = cand
            chip_w = max(84, 28 + len(reading) * 8 + len(word) * 21)
            rounded(draw, (cx, cy, cx + chip_w, cy + 42), 7, "#f8fafc", "#d8e1ee")
            text(draw, (cx + 10, cy + 10), str(i), "#64748b", 13, bold=True)
            text(draw, (cx + 28, cy + 5), word, "#111827", 22, cjk=True, mode=mode)
            text(draw, (cx + 28, cy + 27), reading, "#2563eb", 11, cjk=True, mode=mode)
            cx += chip_w + 8

    if committed:
        text(draw, (66, 246), "Committed", "#64748b", 13)
        text(draw, (150, 236), committed, "#111827", 34, cjk=True, mode=mode)

    text(draw, (42, 326), "Number/click commits a candidate. Space or Enter keeps the English word.", "#58677d", 13)
    return img


def frames_for(mode, active, word, candidates, committed):
    frames = [
        make_frame(mode, "", active=active),
        make_frame(mode, word[:1], active=active),
        make_frame(mode, word[:2], active=active),
        make_frame(mode, word[:3], active=active),
        make_frame(mode, word, candidates[:3], active=active),
        make_frame(mode, word, candidates[:5], active=active),
        make_frame(mode, word, candidates[:5], committed=committed, active=active),
        make_frame(mode, "", committed=committed, active=active),
    ]
    return frames


def save_gif(name, frames):
    durations = [360, 180, 180, 180, 700, 900, 800, 900]
    frames[0].save(
        ASSETS / name,
        save_all=True,
        append_images=frames[1:],
        duration=durations,
        loop=0,
        optimize=True,
    )


def save_clip():
    img = Image.new("RGB", (1200, 630), "#f7f9fc")
    draw = ImageDraw.Draw(img)
    text(draw, (76, 70), "KanjiIME", "#172033", 58, bold=True)
    text(draw, (78, 145), "English to Japanese and Chinese, now with pronunciation hints.", "#526074", 28)

    rounded(draw, (78, 220, 1122, 505), 14, "#ffffff", "#cbd7e6", 2)
    text(draw, (118, 258), "friend", "#172033", 48)
    samples = [
        ("jp", "友達", "(ともだち)", "#2563eb"),
        ("zh", "朋友", "(pengyou)", "#16a34a"),
        ("hk", "朋友", "(pangjau)", "#c2410c"),
    ]
    x = 118
    for mode, word, reading, color in samples:
        rounded(draw, (x, 345, x + 285, 440), 10, "#f8fafc", "#d8e1ee")
        text(draw, (x + 28, 358), word, "#111827", 38, cjk=True, mode=mode)
        text(draw, (x + 28, 408), reading, color, 21, cjk=True, mode=mode)
        x += 320

    text(draw, (78, 552), "Offline Rime IME for Windows and Android", "#526074", 25)
    img.save(ASSETS / "kanjiime-reading-clip.png")


def main():
    ASSETS.mkdir(exist_ok=True)
    save_gif(
        "kanjiime-japanese-demo.gif",
        frames_for(
            "jp",
            "jp",
            "fire",
            [("火", "(ひ)"), ("炎", "(ほのお)"), ("火事", "(かじ)"), ("発火", "(はっか)"), ("火災", "(かさい)")],
            "火",
        ),
    )
    save_gif(
        "kanjiime-simplified-demo.gif",
        frames_for(
            "zh",
            "zh",
            "friend",
            [("朋友", "(pengyou)"), ("好友", "(haoyou)"), ("友人", "(youren)"), ("友", "(you)"), ("知己", "(zhiji)")],
            "朋友",
        ),
    )
    save_gif(
        "kanjiime-traditional-demo.gif",
        frames_for(
            "hk",
            "hk",
            "kind",
            [("善良", "(sinloeng)"), ("友善", "(jausin)"), ("親切", "(cancit)"), ("仁慈", "(janci)"), ("好心", "(housam)")],
            "善良",
        ),
    )
    save_clip()


if __name__ == "__main__":
    main()
