import importlib.util
import tempfile
import unittest
from html.parser import HTMLParser
from pathlib import Path
from PIL import Image

spec = importlib.util.spec_from_file_location('preview', Path(__file__).resolve().parents[1] / 'scripts/post_previews.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

class Head(HTMLParser):
    def __init__(self, source):
        super().__init__()
        self.meta = {}
        self.feed(source)
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == 'meta':
            self.meta[attrs.get('property', attrs.get('name'))] = attrs.get('content')

class Previews(unittest.TestCase):
    def post(self, kind='quote', **extra):
        return {'$id': 'test', 'published': True, 'postType': kind, 'authorName': 'Игорь <writer>', 'content': 'Красивые слова и длинные мысли ' * 100, 'title': 'A title', **extra}

    def test_metadata_and_images(self):
        for kind in ['quote', 'photo', 'link', 'text']:
            with self.subTest(kind=kind), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                p = self.post(kind, linkUrl='https://example.com')
                m.generate([p], root, 'https://example.org/octopus/', False)
                source = (root / 'p/test.html').read_text()
                h = Head(source).meta
                for key in ['og:title', 'og:description', 'og:image', 'og:url', 'og:image:alt']:
                    self.assertTrue(h[key])
                self.assertEqual(h['og:url'], 'https://example.org/octopus/p/test.html')
                self.assertEqual(h['twitter:card'], 'summary_large_image')
                self.assertNotIn('<writer>', source)
                image = root / 'p' / h['og:image'].split('/')[-1]
                with Image.open(image) as im:
                    self.assertEqual(im.size, (1200, 630))
                    self.assertEqual(im.format, 'JPEG')
                    self.assertGreater(len(set(im.resize((100, 50)).getdata())), 20)
                # Fresh generation purges removed/draft posts.
                m.generate([dict(p, published=False)], root, 'https://example.org/octopus/', False)
                self.assertEqual(list((root / 'p').iterdir()), [])

    def test_layout_bounds(self):
        for text in ['Я' * 2000, 'слово ' * 2000, 'Short quote']:
            wrapped = m.lines(text, m.font(30), 530)
            self.assertTrue(all(m.font(30).getlength(line) <= 530 for line in wrapped))
            self.assertEqual(m.card(self.post(content=text), Image.new('RGB', (80, 600), 'red')).size, (1200, 630))

    def test_script_and_attribute_injection(self):
        p = self.post(content='</script><script>alert(1)</script> " &')
        source = m.page(p, 'https://example.org/', 'image.jpg')
        self.assertNotIn('<script>alert', source)
        self.assertEqual(Head(source).meta['og:url'], 'https://example.org/p/test.html')

    def test_parallel_output_matches_serial(self):
        items = [self.post(kind, **{'$id': str(i)})
                 for i, kind in enumerate(['quote', 'photo', 'link', 'text'])]
        with tempfile.TemporaryDirectory() as tmp:
            serial, parallel = Path(tmp) / 'serial', Path(tmp) / 'parallel'
            m.generate(items, serial, 'https://example.org/', False, workers=1)
            m.generate(items, parallel, 'https://example.org/', False, workers=4)
            first = {p.relative_to(serial): p.read_bytes() for p in serial.rglob('*') if p.is_file()}
            second = {p.relative_to(parallel): p.read_bytes() for p in parallel.rglob('*') if p.is_file()}
            self.assertEqual(first, second)

    def test_reject_path_traversal(self):
        with tempfile.TemporaryDirectory() as tmp:
            with self.assertRaises(ValueError):
                m.generate([self.post(**{'$id': '../escape'})], Path(tmp), 'https://example.org/', False)

if __name__ == '__main__':
    unittest.main()
