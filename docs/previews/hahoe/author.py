"""하회탈 아홉 탈: 32x32 바닥 그림을 픽셀 단위로 직접 그린다.

Each mask is authored on its native 32x32 grid. Symmetric masks give the left
half (x 0-15) and are mirrored onto x 16-31; `fix` then lists the pixels that make
a mask lopsided (이매's crooked nose, 초랭이's crooked mouth). Glyphs:

    ' ' transparent        '#' wood/skin, shaded from the top-left light
    '%' hair, shaded        'K' outline (also added round every filled edge)
    'O' hole (eyes, mouth)  'B' black paint (brows)   'R' / 'r' red paint
    '1'-'4' explicit wood tones, dark to bright ('h' hair highlight)

A mirrored highlight drops one step ('4' -> '3'), so the brightest spot stays on
the left; the light comes from above, a little to the left. Run `python author.py preview [outdir]` for the review sheets.
"""
import math
import os
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, '..', '..', '..'))
SIZE = 32

PALETTES = {
    'yangban': {'K': (40, 20, 10), 'O': (22, 10, 6), '1': (128, 62, 24), '2': (178, 98, 40),
                '3': (218, 142, 66), '4': (246, 192, 112), 'B': (30, 22, 18)},
    'halmi': {'K': (26, 10, 8), 'O': (8, 4, 4), '1': (66, 30, 24), '2': (104, 50, 38),
              '3': (142, 78, 58), '4': (180, 116, 88), 'B': (20, 10, 8), 'G': (84, 104, 58)},
    'choraengi': {'K': (38, 16, 10), 'O': (16, 6, 4), '1': (104, 50, 30), '2': (150, 82, 50),
                  '3': (192, 120, 76), '4': (226, 166, 114), 'B': (30, 18, 14)},
    'seonbi': {'K': (34, 14, 10), 'O': (14, 6, 4), '1': (88, 34, 24), '2': (130, 56, 40),
               '3': (172, 88, 62), '4': (210, 130, 96), 'B': (22, 14, 12), 'r': (196, 44, 40)},
    'baekjeong': {'K': (28, 16, 10), 'O': (12, 6, 4), '1': (72, 42, 28), '2': (118, 74, 50),
                  '3': (162, 110, 76), '4': (204, 154, 112), 'B': (22, 14, 10)},
    'bune': {'K': (44, 24, 14), 'O': (24, 12, 8), '1': (138, 86, 40), '2': (186, 128, 62),
             '3': (220, 166, 96), '4': (244, 206, 140), 'B': (40, 28, 22),
             'R': (212, 52, 52), 'r': (150, 34, 36)},
    'jung': {'K': (44, 14, 8), 'O': (22, 6, 4), '1': (124, 42, 22), '2': (176, 72, 40),
             '3': (214, 108, 64), '4': (240, 152, 100), 'B': (50, 18, 12)},
    'gaksi': {'K': (40, 32, 36), 'O': (52, 40, 44), '1': (170, 160, 156), '2': (214, 208, 200),
              '3': (240, 236, 228), '4': (255, 255, 252), 'B': (36, 30, 30),
              'R': (214, 54, 58), 'r': (160, 36, 44)},
    'imae': {'K': (44, 24, 10), 'O': (22, 10, 4), '1': (108, 64, 30), '2': (150, 98, 48),
             '3': (186, 132, 72), '4': (214, 170, 108), 'B': (70, 42, 22)},
}
HAIR = {'%1': (18, 16, 22), '%2': (36, 34, 42), '%3': (62, 62, 76), 'h': (96, 96, 116)}
CORD = {'C': (138, 64, 50), 'c': (86, 38, 30)}

# The tying cord that comes out of each temple and lies on the floor (left side,
# mirrored). Masks with hair hide theirs under it.
CORDS = {
    'long': [(5, 0, 'C'), (4, 1, 'C'), (4, 2, 'c'), (3, 3, 'C'), (3, 4, 'C'), (3, 5, 'C'), (3, 6, 'c'), (3, 7, 'C'), (3, 8, 'C'), (3, 9, 'C'), (3, 10, 'c'), (4, 11, 'C'), (4, 12, 'C'), (4, 13, 'C'), (5, 14, 'c'), (5, 15, 'C'), (4, 16, 'C'), (4, 17, 'C')],
}
CORD_AT = {'yangban': ('long', 11), 'seonbi': ('long', 11), 'baekjeong': ('long', 11), 'jung': ('long', 11),
           'halmi': ('long', 10), 'choraengi': ('long', 9), 'imae': ('long', 10)}

# Left halves, x 0-15, rows y 0-31 (rows not listed are empty).
MASKS = {}

MASKS['yangban'] = dict(top=1, half=[
    "            ####",
    "          ######",
    "         #######",
    "        ####1111",
    "       ###11####",
    "       ##BBBB###",
    "      ##BBBBBB##",
    "      #BB3333BB#",
    "      BB#OOOO#B#",
    "      B#O3333O13",
    "      #2#1111#13",
    "      #3######13",
    "      #133####13",
    "      #133###133",
    "      #133##1343",
    "      ##33#13443",
    "      ##3#1K3332",
    "      ###1#K2222",
    "      ##1##KOK11",
    "      #O1###1111",
    "      #KOO333333",
    "      #K33OOOOOO",
    "       K#333OOOO",
    "       #K##33333",
    "        K#######",
    "        ########",
    "         #######",
    "          ######",
    "           #####",
    "             ###",
])

MASKS['seonbi'] = dict(top=1, half=[
    "            ####",
    "          ######",
    "        ########",
    "       #########",
    "      ##########",
    "      #BB#######",
    "     ##BBBBB##1#",
    "     ####BBBBB1#",
    "     #K####BB1##",
    "     ##KKKK####3",
    "     #r3OO3K##13",
    "     ##KKKK###13",
    "     #33#####111",
    "     #33######33",
    "     #3######111",
    "     ##3####1343",
    "      #3#1344333",
    "      ##1K233322",
    "      ##1KOOK111",
    "       #1##11111",
    "       #1#OOOOOO",
    "       KOO333333",
    "        K#######",
    "        #K######",
    "         #######",
    "         #######",
    "          ######",
    "           #####",
    "             ###",
])

MASKS['baekjeong'] = dict(top=1, half=[
    "            ####",
    "          ######",
    "        ########",
    "       ##1111###",
    "      ###3333###",
    "      #1111###1#",
    "      ##3333##34",
    "      ##BBBBB#13",
    "      #BB###BB11",
    "      ##3OOO3##3",
    "      #3O###O##3",
    "      ##K######3",
    "      ##3K####33",
    "      #1#3KK#133",
    "      #1####1343",
    "      ##1##13443",
    "      ##1#K33333",
    "      #1#1KOO122",
    "      ##1##11111",
    "      #OO#333333",
    "      #KOOOOOOOO",
    "      #K33OOOOOO",
    "      ##K#333333",
    "      ##K#######",
    "      ##K#######",
    "       #########",
    "       #########",
    "        ########",
    "         #######",
])

MASKS['jung'] = dict(top=1, half=[
    "           #####",
    "         #######",
    "        ########",
    "       #########",
    "      ##########",
    "      ########34",
    "     ##1111##344",
    "     #13333#1333",
    "     #BBBBBB#111",
    "     ##3OOO3###3",
    "     #3O###O###3",
    "     ##1111####3",
    "     #3#111####3",
    "     #3#######33",
    "     #3#####1343",
    "     ##3###13443",
    "     ###1#KOO322",
    "     ###1##11111",
    "     #OO#3333333",
    "     #KOOOOOOOOO",
    "     #KOOOOOOOOO",
    "      K3OOOOOOOO",
    "      #K33333333",
    "       K########",
    "       #########",
    "        ########",
    "         #######",
    "          ######",
    "            ####",
])

MASKS['gaksi'] = dict(top=0, half=[
    "      %%%%%%%%%%",
    "    %%h%%h%%h%%%",
    "   %%h%%h%%h%%h%",
    "   %%%%%%%%%%%%%",
    "   %%%%%%%%%####",
    "   %%%%%%%######",
    "   %%%%%%#######",
    "   %%%%%########",
    "   %%%%%######RR",
    "   %%%%%#####RRR",
    "   %%%%%#####RRR",
    "   %%%%%#BBBB#RR",
    "   %%%%%B######3",
    "   %%%%%#OOOO##3",
    "   %%%%%#######3",
    "   %%%%%##RRR##3",
    "   %%%%%#RRRRR33",
    "   %%%%%#RRRRR#3",
    "   %%%%%##RRR#23",
    "   %%%%%######12",
    "   %%%%%#######1",
    "   %%%%%########",
    "   %%%%%######rr",
    "   %%%%%%#####RR",
    "   %%h%%%%######",
    "    %%h%%%%#####",
    "    %%%h%%  ####",
    "     %%%h%   ###",
    "    %%  %%      ",
    "    %%  %       ",
    "     %%%        ",
])

MASKS['bune'] = dict(top=1, half=[
    "         %%%%%%%",
    "       %%h%%%%%%",
    "      %%h%%%%%%%",
    "     %%%%%%%%%%%",
    "     %%%%%######",
    "     %%%########",
    "     %%%######RR",
    "     %%######RRR",
    "     %%######RRR",
    "     %%#######RR",
    "     %%##BBB####",
    "     %%#B###B##3",
    "     %%##OOO###3",
    "     %%#O###O##3",
    "     %%########3",
    "     %%#RRR###33",
    "     %#RRRRR##33",
    "      #RRRRR#343",
    "      ##RRR##122",
    "      #######111",
    "       #####r###",
    "       ######RRR",
    "        ########",
    "         #######",
    "          ######",
    "            ####",
])

MASKS['halmi'] = dict(top=1, half=[
    "              ##",
    "             ###",
    "            ####",
    "           #####",
    "          ##1###",
    "         ##11##1",
    "        ##111###",
    "       ##1KK1###",
    "      ##KOOK###3",
    "      ##KOOK###3",
    "      #1#1KK1##3",
    "      #1#1111##3",
    "      ##1#####33",
    "      #1######13",
    "      #1#1####K3",
    "      ##1#1##1O2",
    "      #1#1###111",
    "       #1#1#3333",
    "       #1#1#3OOO",
    "        #1#3OOOO",
    "         #13OOOO",
    "          #13OOO",
    "           #1333",
    "            ##11",
    "             ###",
    "              ##",
])

MASKS['choraengi'] = dict(top=2, half=[
    "           #####",
    "         ####34#",
    "        ##34443#",
    "       ##3443333",
    "       ###33333#",
    "       ##111111#",
    "       ##1KK1###",
    "       #1KOOK##3",
    "       #1KOOK##3",
    "       #1OKK###3",
    "       #O######3",
    "        #1##1343",
    "        #1##1443",
    "        ##1KOK22",
    "         #1#1111",
    "         #######",
    "          ######",
    "          ######",
    "           #####",
    "            ####",
    "             ###",
])

MASKS['imae'] = dict(top=3, half=[
    "           #####",
    "         #######",
    "        ########",
    "       ###1111##",
    "      ##########",
    "      ###BBB####",
    "     ##B###B####",
    "     #####OOO##3",
    "     ###OOOO###3",
    "     #OOO######3",
    "     #1########3",
    "     #1#######33",
    "     ##1######33",
    "     ###1####1KK",
    "     ####1###KO2",
    "     #####1##111",
    "     #1####1#333",
    "     ##1###33333",
    "      O1#3333333",
    "       OOOOOOOOO",
])

# Pixels that break the mirror (x, y, glyph), applied after mirroring.
FIXES = {
    # 할미: green age spots over the dark red paint
    'halmi': [(9, 6, 'G'), (19, 9, 'G'), (8, 15, 'G'), (22, 13, 'G'), (12, 5, 'G'), (21, 18, 'G'), (10, 20, 'G')],
    # 초랭이: a pursed, crooked harelip mouth slanting up to one side, one nostril higher
    'choraengi': [(12, 19, 'K'), (13, 19, 'K'), (14, 18, 'K'), (15, 18, 'K'), (16, 18, 'K'), (17, 18, 'K'), (18, 17, 'K'), (19, 17, 'K'), (20, 17, 'K'), (14, 17, 'K'), (12, 18, '3'), (13, 18, '3'), (15, 17, '3'), (16, 17, '3'), (18, 14, 'O'), (19, 15, '1'), (18, 15, 'K')],
    # 백정: a sneer, one corner of the grin pulled higher, and a crooked forehead
    'baekjeong': [(24, 19, 'O'), (23, 19, 'O'), (21, 6, '#'), (22, 6, '#'), (23, 6, '#'), (24, 6, '#'), (21, 5, '1'), (22, 5, '1'), (23, 5, '1'), (24, 5, '1'), (19, 4, '1'), (20, 4, '1'), (21, 4, '1'), (22, 4, '1'), (19, 5, '3'), (20, 5, '3')],
    # 이매: lopsided grin (one corner higher) and a nose broken off at a slant
    'imae': [(25, 20, 'O'), (25, 21, ' '), (24, 21, 'O'), (17, 16, '1'), (16, 16, 'K')],
}

ORDER = ['yangban', 'halmi', 'choraengi', 'seonbi', 'baekjeong', 'bune', 'jung', 'gaksi', 'imae']

INFO = {
    'yangban': ('양반탈', '보물방', '거드름 피우는 양반, 턱이 따로 움직여 크게 웃는다',
                ['거드름: 쏘지 않고 가만히 서 있는 동안', '웃어넘기기 확률 2배']),
    'halmi': ('할미탈', '상점', '영감이 사 온 청어를 혼자 다 먹는 할미',
              ['혼자 다 먹기: 방의 픽업이 나에게 끌려오고,', '상점 물건 10% 할인']),
    'choraengi': ('초랭이탈', '비밀방', '양반의 하인, 재빠르고 경망스러워 양반을 놀린다',
                  ['이동 속도 +0.3,', '놀림 혼란 시간 2배']),
    'seonbi': ('선비탈', '도서관', '사서삼경을 다 읽었다고 뽐내는 선비',
               ['방을 깰 때 액티브 충전 한 칸 더,', '행운 +1']),
    'baekjeong': ('백정탈', '희생방', '소를 잡아 염통과 소불알을 파는 백정',
                  ['공격력 +1, 적을 죽이면 5% 확률로', '염통(빨간 하트 반 칸)']),
    'bune': ('부네탈', '아케이드', '중을 홀린 요염한 부네',
             ['내 눈물에 맞은 적 10% 확률로', '홀림(아군, 5초)']),
    'jung': ('중탈', '악마방', '부네에게 반해 계를 깬 파계승',
             ['악마방 거래 값이 하트 한 칸 싸짐', '(최소 한 칸)']),
    'gaksi': ('각시탈', '천사방', '마을 신(서낭각시), 무동을 타고 마을에 든다',
              ['층에 들어설 때 소울 하트 한 칸,', '웃어넘기기 +15%p']),
    'imae': ('이매탈', '저주방', '턱이 없어 늘 웃는 선비의 하인',
             ['웃어넘기기 +20%p, 대신 맞으면', '웃음이 터져 0.5초 멈칫']),
}

# What the masks follow: the Hahoe Byeolsingut Talnori Preservation Society's
# description of each mask (hahoemask.co.kr, 하회탈 개요), with Wikipedia and the
# Encyclopedia of Korean Culture for 이매 (the society's page repeats 할미 there).
NOTES = {
    'yangban': '부드러운 선의 호탕한 웃음, 크게 휜 눈썹과 초승달 눈, 큰 코. 턱을 끈으로 따로 매달았다',
    'halmi': '정수리가 위로 뾰족, 아래턱이 앞으로 뾰족. 검붉은 얼굴에 녹색 기미, 동그랗게 깊이 판 눈, 휑하니 뚫린 이 빠진 입',
    'choraengi': '앞짱구 이마, 올챙이 눈, 끝이 뭉툭한 주먹코, 비뚤어진 언챙이 입. 좌우가 다르다',
    'seonbi': '도끼눈에 치켜 올라간 눈꼬리, 충혈된 눈, 찡그린 미간과 콧날, 곤두선 눈썹, 넓은 코끝, 역삼각형 얼굴, 따로 단 턱',
    'baekjeong': '이마의 깊은 주름, 눈 아래 칼질 자국, 미간의 혹, 넓은 콧방울, 각진 턱, 비웃는 입',
    'bune': '갸름한 얼굴, 반달 눈썹, 오똑한 코, 작은 입, 이마와 볼의 연지·곤지, 귀밑까지 내려온 검은 머리',
    'jung': '주홍 얼굴, 미간의 큰 혹, 초승달 실눈과 그 아래 주름, 들린 코끝, 박장대소하듯 벌린 입',
    'gaksi': '분 바른 얼굴에 연지·곤지·붉은 입술, 아래로 깐 실눈, 꾹 다문 입, 턱 아래까지 늘어져 끝이 고리진 머리채',
    'imae': '턱이 없다. 길고 가늘게 처진 눈웃음, 부드러운 눈썹, 떨어져 나간 코끝, 좌우가 다르다',
}

MIRROR = {'4': '3', 'h': '%'}


def grid(key):
    spec = MASKS[key]
    g = [[' '] * SIZE for _ in range(SIZE)]
    for i, row in enumerate(spec['half']):
        if len(row) != 16:
            raise ValueError('%s row %d is %d wide' % (key, i, len(row)))
        y = spec['top'] + i
        for x, ch in enumerate(row):
            g[y][x] = ch
            g[y][SIZE - 1 - x] = MIRROR.get(ch, ch)
    for x, y, ch in FIXES.get(key, []):
        g[y][x] = ch
    return g


def shade(key):
    """Resolve '#' and '%' into tones and add the outline; returns glyph rows."""
    g = grid(key)
    face = [(x, y) for y in range(SIZE) for x in range(SIZE) if g[y][x] not in ' %']
    x0 = min(p[0] for p in face); x1 = max(p[0] for p in face)
    y0 = min(p[1] for p in face); y1 = max(p[1] for p in face)
    cx, cy = (x0 + x1 + 1) / 2, (y0 + y1 + 1) / 2
    hw, hh = (x1 - x0 + 1) / 2, (y1 - y0 + 1) / 2
    filled = [[g[y][x] != ' ' for x in range(SIZE)] for y in range(SIZE)]
    out = [row[:] for row in g]

    def edge(x, y):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if not (0 <= nx < SIZE and 0 <= ny < SIZE) or not filled[ny][nx]:
                return True
        return False

    for y in range(SIZE):
        for x in range(SIZE):
            ch = g[y][x]
            if ch == ' ':
                continue
            if ch in '#%' and edge(x, y):
                out[y][x] = 'K'
                continue
            if ch == '#':
                u = (x + 0.5 - cx) / hw
                v = (y + 0.5 - cy) / hh
                z = math.sqrt(max(0.04, 1 - 0.8 * u * u - 0.5 * v * v))
                d = (-0.15 * u - 0.30 * v + 0.90 * z)
                if any(0 <= x + dx < SIZE and g[y][x + dx] == '%' for dx in (-1, 1)) or \
                        any(0 <= y + dy < SIZE and g[y + dy][x] == '%' for dy in (-1, 1)):
                    out[y][x] = '1'
                elif d > 1.12:
                    out[y][x] = '4'
                elif d > 0.95:
                    out[y][x] = '3'
                elif d > 0.55:
                    out[y][x] = '2'
                else:
                    out[y][x] = '1'
            elif ch == '%':
                u = (x + 0.5 - cx) / (hw + 3)
                v = (y + 0.5 - cy) / (hh + 2)
                d = -0.6 * u - 0.6 * v
                out[y][x] = '%3' if d > 0.45 else ('%2' if d > -0.2 else '%1')
    return out


def image(key):
    pal = dict(PALETTES[key]); pal.update(HAIR); pal.update(CORD)
    rows = shade(key)
    if key in CORD_AT:
        shape, cy = CORD_AT[key]
        for dx, dy, ch in CORDS[shape]:
            for x in (dx, SIZE - 1 - dx):
                if 0 <= cy + dy < SIZE and rows[cy + dy][x] == ' ':
                    rows[cy + dy][x] = ch
    im = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    px = im.load()
    for y in range(SIZE):
        for x in range(SIZE):
            ch = rows[y][x]
            if ch != ' ':
                px[x, y] = pal[ch] + (255,)
    return im


def big(im, k):
    return im.resize((im.width * k, im.height * k), Image.NEAREST)


def font(size, bold=False):
    return ImageFont.truetype('C:/Windows/Fonts/malgunbd.ttf' if bold else 'C:/Windows/Fonts/malgun.ttf', size)


def floor_tile(w, h):
    path = os.path.join(ROOT, '..', '..', 'extracted_resources', 'resources', 'gfx', 'backdrop', '01_basement_nfloor.png')
    try:
        src = Image.open(path).convert('RGBA')
        tile = Image.new('RGBA', (w, h), (70, 56, 48, 255))
        for yy in range(0, h, src.height):
            for xx in range(0, w, src.width):
                tile.alpha_composite(src, (xx, yy))
        return tile
    except OSError:
        return Image.new('RGBA', (w, h), (70, 56, 48, 255))


def sheet(out):
    ims = {k: image(k) for k in ORDER}
    cw, ch = 640, 360
    head = 120
    foot = 150
    W, H = cw * 3, head + ch * 3 + foot
    s = Image.new('RGBA', (W, H), (24, 22, 26, 255))
    d = ImageDraw.Draw(s)
    d.text((24, 20), '하회탈 아홉 탈 (32x32 바닥 그림, 초안)', font=font(34, True), fill=(240, 232, 214))
    d.text((24, 70), '방마다 정해진 탈이 하나씩 놓이고, 닿으면 그 탈로 바꿔 씁니다. 쓰던 탈은 그 자리에 벗어 둡니다.',
           font=font(19), fill=(190, 182, 170))
    floor = floor_tile(256, 256)
    for i, k in enumerate(ORDER):
        x, y = (i % 3) * cw, head + (i // 3) * ch
        d.rounded_rectangle((x + 10, y + 8, x + cw - 10, y + ch - 8), 14, fill=(36, 33, 38, 255), outline=(70, 64, 72, 255))
        bg = floor.copy()
        shadow = Image.new('RGBA', (256, 256), (0, 0, 0, 0))
        ImageDraw.Draw(shadow).ellipse((40, 214, 216, 246), fill=(0, 0, 0, 90))
        bg.alpha_composite(shadow)
        bg.alpha_composite(big(ims[k], 8))
        s.alpha_composite(bg, (x + 24, y + 26))
        s.alpha_composite(big(ims[k], 1), (x + 290, y + 30))
        s.alpha_composite(big(ims[k], 2), (x + 330, y + 22))
        name, room, who, eff = INFO[k]
        d.text((x + 404, y + 22), name, font=font(30, True), fill=(250, 240, 220))
        d.text((x + 292, y + 96), room + '에 놓임', font=font(20, True), fill=(236, 186, 92))
        tx, ty = x + 292, y + 132
        for line in wrap(who, 15):
            d.text((tx, ty), line, font=font(16), fill=(170, 164, 156)); ty += 22
        ty += 10
        for line in eff:
            d.text((tx, ty), line, font=font(18, True), fill=(226, 236, 246)); ty += 26
        ty = y + 292
        d.text((x + 24, ty), '생김새', font=font(14, True), fill=(150, 170, 196))
        for line in wrap(NOTES[k], 36):
            d.text((x + 76, ty), line, font=font(14), fill=(150, 160, 176)); ty += 20
    by = head + ch * 3 + 12
    d.text((24, by), '바탕 효과 (어느 탈을 쓰든)', font=font(22, True), fill=(240, 232, 214))
    d.text((24, by + 40), '웃어넘기기: 맞을 때 25% 확률로 피해를 받지 않음 (행운 1당 +2.5%p, 최대 60%)', font=font(19), fill=(210, 204, 196))
    d.text((24, by + 72), '놀림: 나를 때린 적이 3초 혼란 (보스는 1초)', font=font(19), fill=(210, 204, 196))
    d.text((24, by + 104), '탈을 처음 쓰기 전에는 맨 하회탈(바탕 효과만). 쓴 탈은 층을 넘어가도 그대로이고 플레이어마다 따로입니다.',
           font=font(17), fill=(160, 154, 146))
    s.save(out)


def wrap(text, n):
    words, lines, cur = text.split(' '), [], ''
    for w in words:
        if cur and len(cur) + 1 + len(w) > n:
            lines.append(cur); cur = w
        else:
            cur = (cur + ' ' + w) if cur else w
    if cur:
        lines.append(cur)
    return lines


def strip(out, scale):
    ims = [image(k) for k in ORDER]
    pad = 4
    s = Image.new('RGBA', ((SIZE + pad) * len(ims) * scale, (SIZE + pad * 2) * scale), (54, 46, 42, 255))
    for i, im in enumerate(ims):
        s.alpha_composite(big(im, scale), ((SIZE + pad) * i * scale + pad * scale // 2, pad * scale))
    s.save(out)


def scene(out):
    """Every mask lying on a basement floor at gameplay scale (x2 for the screen)."""
    floor = floor_tile(52 * 9 + 40, 120)
    for i, k in enumerate(ORDER):
        x = 20 + i * 52 + 10
        sh = Image.new('RGBA', floor.size, (0, 0, 0, 0))
        ImageDraw.Draw(sh).ellipse((x + 4, 72, x + 28, 80), fill=(0, 0, 0, 80))
        floor.alpha_composite(sh)
        floor.alpha_composite(image(k), (x, 46))
    big(floor, 3).save(out)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else 'preview'
    outdir = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, '.tmp', 'hahoe')
    os.makedirs(outdir, exist_ok=True)
    if cmd == 'preview':
        sheet(os.path.join(outdir, 'hahoe_masks_sheet.png'))
        strip(os.path.join(outdir, 'hahoe_masks_1x.png'), 1)
        strip(os.path.join(outdir, 'hahoe_masks_x8.png'), 8)
        scene(os.path.join(outdir, 'hahoe_masks_floor.png'))
        for k in ORDER:
            image(k).save(os.path.join(outdir, 'mask_%s.png' % k))
        print('wrote', outdir)
    else:
        raise SystemExit('usage: author.py preview [outdir]')


if __name__ == '__main__':
    main()
