#!/usr/bin/env python3
import html
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ZH = ROOT / "docs/index.html"
EN = ROOT / "docs/en/index.html"
STRINGS = json.loads((Path(__file__).parent / "en.json").read_text())


def inner_end(s, tag, start):
    depth, i = 1, start
    pat = re.compile(rf"<(/?){tag}\b[^>]*>", re.I)
    while True:
        m = pat.search(s, i)
        if not m:
            raise ValueError(f"<{tag}> 沒有結束標籤")
        depth += -1 if m.group(1) else 1
        if depth == 0:
            return m.start(), m.end()
        i = m.end()


def apply_strings(s, strings):
    missing = []

    def text(key):
        if key not in strings:
            missing.append(key)
            return None
        return strings[key]

    def attr_sub(m):
        tag = m.group(0)
        for name, key in re.findall(r'data-i-([\w-]+)="([^"]+)"', tag):
            v = text(key)
            if v is not None:
                tag = re.sub(rf'(\s{name}=")[^"]*(")', lambda x: x.group(1) + html.escape(v, quote=True) + x.group(2), tag)
        return tag

    s = re.sub(r"<[^>]*\sdata-i-[\w-]+=\"[^>]*>", attr_sub, s)
    out, pos = [], 0
    for m in re.finditer(r'<(\w+)\b[^>]*\sdata-i="([^"]+)"[^>]*>', s):
        if m.start() < pos:
            continue
        tag, key = m.group(1), m.group(2)
        end, _ = inner_end(s, tag, m.end())
        v = text(key)
        out.append(s[pos:m.end()])
        out.append(s[m.end():end] if v is None else v)
        pos = end
    out.append(s[pos:])
    return "".join(out), missing


def faq_jsonld(s):
    items = []
    for q, a in re.findall(r"<details[^>]*>\s*<summary[^>]*>(.*?)</summary>(.*?)</details>", s, re.S):
        a = re.sub(r"<button.*?</button>", "", a, flags=re.S)
        a = re.sub(r"</(p|li|div)>", " ", a)
        clean = lambda t: html.unescape(re.sub(r"\s+", " ", re.sub(r"<[^>]+>", "", t))).strip()
        items.append({"@type": "Question", "name": clean(q),
                      "acceptedAnswer": {"@type": "Answer", "text": clean(a)}})
    data = {"@context": "https://schema.org", "@type": "FAQPage", "mainEntity": items}
    return json.dumps(data, ensure_ascii=False, separators=(",", ":"))


def set_faq(s):
    return re.sub(r'(<script type="application/ld\+json" id="ld-faq">).*?(</script>)',
                  lambda m: m.group(1) + faq_jsonld(s) + m.group(2), s, flags=re.S)


zh = ZH.read_text()
zh = set_faq(zh)
ZH.write_text(zh)

en, missing = apply_strings(zh, STRINGS)
if missing:
    sys.exit("en.json 缺少：" + ", ".join(sorted(set(missing))))
en = en.replace('<html lang="zh-Hant">', '<html lang="en">', 1)
en = en.replace('data-lang="zh" class="on"', 'data-lang="zh"').replace('data-lang="en"', 'data-lang="en" class="on"')
en = set_faq(en)
EN.parent.mkdir(exist_ok=True)
EN.write_text(en)
print(f"OK：{ZH.relative_to(ROOT)}、{EN.relative_to(ROOT)}")
