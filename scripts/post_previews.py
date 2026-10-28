#!/usr/bin/env python3
"""Generate public, crawler-readable share pages. Never uses an API key."""
import argparse
import hashlib
import html
import io
import json
import re
import shutil
import time
from pathlib import Path
from urllib.parse import urlencode, quote, urlsplit
from urllib.request import Request, urlopen
from PIL import Image, ImageDraw, ImageFont, ImageOps

ROOT = Path(__file__).resolve().parents[1]
CONFIG = (ROOT / 'js/config.js').read_text()
def config(name):
    return re.search(r'const\s+' + name + r"\s*=\s*'([^']+)'", CONFIG)[1]
ENDPOINT = config('APPWRITE_ENDPOINT')
PROJECT = config('APPWRITE_PROJECT_ID')

def public_get(path, params=None):
    url = ENDPOINT + path + ('?' + urlencode(params) if params else '')
    for attempt in range(3):
        try:
            with urlopen(Request(url, headers={'X-Appwrite-Project': PROJECT}), timeout=30) as r:
                data = r.read(20_000_001)
                if len(data) > 20_000_000:
                    raise ValueError('Public response exceeds 20 MB')
                return data
        except Exception:
            if attempt == 2:
                raise
            time.sleep(attempt + 1)

def posts():
    cursor = None
    while True:
        queries = [json.dumps({'method': 'limit', 'values': [100]})]
        if cursor:
            queries.append(json.dumps({'method': 'cursorAfter', 'values': [cursor]}))
        # Explicitly anonymous reads respect collection/document permissions.
        page = json.loads(public_get('/databases/' + config('APPWRITE_DB_ID') + '/collections/' + config('COL_POSTS') + '/documents', [('queries[]', q) for q in queries]))['documents']
        yield from (p for p in page if p.get('published') is True)
        if len(page) < 100:
            break
        cursor = page[-1]['$id']

def plain(value):
    value = re.sub(r'!\[[^]]*\]\([^)]*\)', '', value or '')
    value = re.sub(r'\[([^]]+)\]\([^)]*\)', r'\1', value)
    return ' '.join(html.unescape(re.sub(r'<[^>]*>|[#*`_~]', '', value)).split())

def shorten(text, size):
    return text if len(text) <= size else text[:size-1].rstrip() + '…'

def fields(p):
    kind = p.get('postType') or 'text'
    body = plain(p.get('content'))
    title = body if kind == 'quote' else plain(p.get('title')) or body or 'Photo'
    return kind, title or 'Octopus post', body

def font(size, serif=False):
    return ImageFont.truetype('DejaVuSerif.ttf' if serif else 'DejaVuSans.ttf', size)

def lines(text, f, width):
    # Character wrapping also handles URLs and words without spaces.
    out, line = [], ''
    for word in text.split():
        candidate = (line + ' ' + word).strip()
        if f.getlength(candidate) <= width:
            line = candidate
            continue
        if line:
            out.append(line)
        line = ''
        for char in word:
            if f.getlength(line + char) > width:
                out.append(line)
                line = ''
            line += char
    if line:
        out.append(line)
    return out

def text_block(draw, text, box, serif=False, maximum=58):
    x, y, width, height = box
    for size in range(maximum, min(30, maximum) - 1, -2):
        f = font(size, serif)
        wrapped = lines(text, f, width)
        if len(wrapped) * size * 1.3 <= height:
            break
    count = max(1, int(height / (size * 1.3)))
    if len(wrapped) > count:
        wrapped = wrapped[:count]
        last = wrapped[-1]
        while f.getlength(last + '…') > width:
            last = last[:-1]
        wrapped[-1] = last.rstrip() + '…'
    for i, line in enumerate(wrapped):
        draw.text((x, y + i * size * 1.3), line, font=f, fill='#173c3b')

def card(p, photo=None):
    kind, title, body = fields(p)
    im = Image.new('RGB', (1200, 630), '#f5f2e9')
    d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 15, 630), fill='#0e8f86')
    d.text((60, 36), 'Octopus', font=font(30), fill='#0e8f86')
    d.text((60, 85), {'quote': 'WORDS WORTH KEEPING', 'photo': 'A MOMENT, SHARED', 'link': 'WORTH EXPLORING'}.get(kind, 'IDEAS WORTH SHARING'), font=font(15), fill='#607c78')
    width = 530 if photo else 1080
    text_block(d, ('“' + title + '”') if kind == 'quote' else title, (60, 143, width, 285), kind == 'quote')
    detail = plain(p.get('quoteSource')) if kind == 'quote' else (urlsplit(p.get('linkUrl') or '').hostname if kind == 'link' else body)
    if detail and detail != title:
        text_block(d, detail, (60, 447, width, 58), maximum=30)
    d.line((60, 537, 60 + width, 537), fill='#c9d5cc', width=2)
    text_block(d, 'Shared by ' + plain(p.get('authorName') or 'Octopus writer'), (60, 560, width, 40), maximum=24)
    if photo:
        im.paste(ImageOps.fit(ImageOps.exif_transpose(photo).convert('RGB'), (535, 630), method=Image.Resampling.LANCZOS), (665, 0))
    return im

def page(p, base, image):
    kind, title, body = fields(p)
    identifier = quote(p['$id'], safe='')
    url = base + 'p/' + identifier + '.html'
    target = base + 'post.html?id=' + identifier
    description = shorten(' · '.join(filter(None, [plain(p.get('authorName')), body, plain(p.get('quoteSource')), plain(p.get('userText'))])), 240)
    title = shorten(title, 100)
    e = html.escape
    tags = {'og:type': 'article', 'og:site_name': 'Octopus', 'og:title': title, 'og:description': description, 'og:url': url, 'og:image': base + 'p/' + image, 'og:image:width': '1200', 'og:image:height': '630', 'og:image:type': 'image/jpeg', 'og:image:alt': shorten(title + ' — ' + plain(p.get('authorName')), 200)}
    meta = '\n'.join(f'<meta property="{k}" content="{e(v, quote=True)}">' for k, v in tags.items())
    return f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>{e(title)} — Octopus</title>
{meta}
<meta name="description" content="{e(description, quote=True)}"><meta name="twitter:card" content="summary_large_image"><link rel="canonical" href="{e(url, quote=True)}">
<style>body{{font:20px/1.6 system-ui;max-width:850px;margin:40px auto;padding:20px;color:#173c3b;background:#f5f2e9}}img{{width:100%;border-radius:16px}}a{{color:#0e8f86}}p{{white-space:pre-wrap}}</style></head><body><a href="{e(base, quote=True)}">Octopus</a><article><h1>{e(title)}</h1><img src="{e(image, quote=True)}" alt="{e(title, quote=True)}"><p>{e(description)}</p><a href="{e(target, quote=True)}">Read full post and comments →</a></article>
<script>location.replace({json.dumps(target).replace('<', r'\u003c')});</script></body></html>'''

def generate(items, output, base, fetch_images=True):
    if not base.startswith('https://') or urlsplit(base).query or urlsplit(base).fragment:
        raise ValueError('SITE_URL must be an absolute HTTPS directory URL')
    base = base.rstrip('/') + '/'
    destination = output / 'p'
    shutil.rmtree(destination, ignore_errors=True)  # Deleted/unpublished posts disappear on every successful deploy.
    destination.mkdir(parents=True)
    ready = []
    for p in items:
        if p.get('published') is not True:
            continue
        if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,35}', p['$id']):
            raise ValueError('Invalid post ID')
        photo = None
        if fetch_images and p.get('imageId'):
            try:
                raw = public_get('/storage/buckets/' + config('APPWRITE_BUCKET_ID') + '/files/' + quote(p['imageId'], safe='') + '/view')
                photo = Image.open(io.BytesIO(raw))
                photo.load()
            except Exception as err:
                print(f"Image unavailable for {p['$id']}: {type(err).__name__}; using typography card")
        buffer = io.BytesIO()
        card(p, photo).save(buffer, 'JPEG', quality=90, optimize=True)
        data = buffer.getvalue()
        image = p['$id'] + '-' + hashlib.sha256(data).hexdigest()[:12] + '.jpg'
        (destination / image).write_bytes(data)
        (destination / (p['$id'] + '.html')).write_text(page(p, base, image), encoding='utf-8')
        ready.append(p['$id'])
    (output / 'share-posts.json').write_text(json.dumps(ready))
    print(f'Generated {len(ready)} public previews')

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', type=Path, default=ROOT / 'dist')
    parser.add_argument('--site-url', required=True)
    args = parser.parse_args()
    generate(list(posts()), args.output, args.site_url)
