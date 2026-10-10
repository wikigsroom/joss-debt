"""Approved publication typography: the only visible lettering is 香火债."""
from PIL import Image, ImageDraw

from create_logo_candidates import font, text_center

GAME_TITLE = "香火债"
PAPER, INK, RED = "#F0DFC0", "#242725", "#BC3C2F"


def draw_title(draw, center_x, top, size, light=True):
    face = font("SmileySans-Oblique.ttf", size)
    offset_x, offset_y = max(2, round(size * .024)), max(3, round(size * .035))
    text_center(draw, center_x + offset_x, top + offset_y, GAME_TITLE, face, RED)
    text_center(draw, center_x, top, GAME_TITLE, face, PAPER if light else INK)


def wordmark(size=(2400, 840), light=True):
    image = Image.new("RGBA", size, (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    point_size = int(size[1] * .80)
    while True:
        face = font("SmileySans-Oblique.ttf", point_size)
        bounds = draw.textbbox((0, 0), GAME_TITLE, font=face)
        width, height = bounds[2] - bounds[0], bounds[3] - bounds[1]
        if width <= size[0] * .86 and height <= size[1] * .75:
            break
        point_size -= 1
    draw_title(draw, size[0] / 2, (size[1] - height) / 2 - point_size * .02, point_size, light)
    return image
