"""Rebuilds the Noto Sans JP/KR/SC subsets in assets/fonts from the full Bold fonts, keeping every character
used in i18n/*.json plus currency signs and punctuation. Run after adding Japanese, Korean or Chinese text.
   python3 tools/fonts/subset_cjk.py <dir with NotoSansJP_700Bold.ttf, NotoSansKR_700Bold.ttf, NotoSansSC_700Bold.ttf>
Full fonts: npm packages @expo-google-fonts/noto-sans-jp|kr|sc (folder 700Bold), SIL OFL 1.1."""
import json, os, sys, glob
from fontTools.ttLib import TTFont
from fontTools import subset

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
src = sys.argv[1]
LANGS = ['uk', 'en', 'pl', 'de', 'es', 'fr', 'it', 'pt_BR', 'tr', 'ja', 'ko', 'zh_CN']


def chars(l):
    s = set()
    for v in json.load(open(os.path.join(ROOT, 'i18n', l + '.json'), encoding='utf-8')).values():
        for x in (v.values() if isinstance(v, dict) else [v]):
            s.update(x)
    return s


allc = {l: chars(l) for l in LANGS}
native = 'УкраїнськаEnglishPolskiDeutschEspañolFrançaisItalianoPortuguês (Brasil)Türkçe日本語한국어简体中文'
latin = set().union(*[allc[l] for l in LANGS if l not in ('ja', 'ko', 'zh_CN')]) | set(native) | set('0123456789+×→…')
currency = set(chr(c) for c in range(0x20A0, 0x20C1)) | set('$€£¥₩₹₺₴₽¢฿₫₱₪') | {' ', ' ', ' '}
basic = set(chr(c) for c in range(0x20, 0x7f)) | set('…→×·•«»„“”‘’—–　、。，：；！？（）「」『』【】・ー〜％')
for l, pat, name in [('ja', 'NotoSansJP_700Bold.ttf', 'NotoSansJP-Bold'), ('ko', 'NotoSansKR_700Bold.ttf', 'NotoSansKR-Bold'),
                     ('zh_CN', 'NotoSansSC_700Bold.ttf', 'NotoSansSC-Bold')]:
    path = glob.glob(os.path.join(src, '**', pat), recursive=True)[0]
    text = allc[l] | set(native) | currency | basic | (latin if l == 'zh_CN' else set())
    font = TTFont(path)
    cmap = font.getBestCmap()
    have = ''.join(sorted(c for c in text if ord(c) in cmap))
    lack = sorted(c for c in allc[l] if ord(c) not in cmap)
    o = subset.Options()
    o.layout_features = ['*']
    o.name_IDs = ['*']
    o.notdef_outline = True
    o.hinting = False
    sub = subset.Subsetter(o)
    sub.populate(text=have)
    sub.subset(font)
    dst = os.path.join(ROOT, 'assets', 'fonts', name + '.ttf')
    font.save(dst)
    print(name, len(have), 'characters', os.path.getsize(dst) // 1024, 'KB', 'not in font:', lack)
