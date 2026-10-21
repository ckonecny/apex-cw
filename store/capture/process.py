import os, shutil
from PIL import Image
R=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..')
W=os.path.dirname(os.path.abspath(__file__))
def crop(p): return Image.open(p).convert('RGB').crop((0,140,1080,2374))
store={'home':'home','hear':'hear','hear_stats':'hear_stats','miniqso':'verstehen','exam':'exam','send':'send','qso':'qso','games':'games'}
site={'home':'home','hear':'hear','qrm':'qrm','hear_stats':'stats','streak':'streak','verstehen':'verstehen','exam':'exam','examcustom':'examcustom','games':'games','zork':'zork'}
for lang in ('de','en'):
    for src,dst in store.items():
        p=f'{W}/raw/{lang}/{src}.png'
        if os.path.exists(p): crop(p).save(f'{R}/store/raw/{lang}/{dst}.png',optimize=True)
    for src,dst in site.items():
        p=f'{W}/raw/{lang}/{src}.png'
        if os.path.exists(p): crop(p).resize((720,1489),Image.LANCZOS).save(f'{R}/site/img/{lang}_{dst}.webp',quality=82,method=6)
    for t in range(1,8):
        p=f'{W}/raw/themes_{1 if lang=='en' else 0}/t{t}.png'
        if os.path.exists(p): crop(p).save(f'{R}/store/raw/{lang}/theme_{t}.png',optimize=True)
