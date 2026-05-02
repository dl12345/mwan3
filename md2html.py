#!/usr/bin/env python3
"""
md2html.py  -  Convert mwan3 README.md to styled HTML.

Usage: python3 md2html.py <output.html>

Input is always README.md in the same directory as this script.

Code fence language hints used in the README:
  ```diagram   centred ASCII-art component map (.diagram wrapper)
  ```flow       left-bordered service flow sequence (.chain-box wrapper)
  (all others) plain <pre><code> block
"""

import re
import sys
import os

README_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'README.md')

# ─── CSS (identical styling to mwan3-nftables-internals.html) ────────────────

CSS = """\
  :root {
    --bg: #fdfdfd; --fg: #1a1a1a; --accent: #2563eb; --accent-light: #dbeafe;
    --code-bg: #f3f4f6; --border: #d1d5db; --heading: #111827;
    --note-bg: #fffbeb; --note-border: #f59e0b;
    --warn-bg: #fef2f2; --warn-border: #ef4444;
    --chain-bg: #ecfdf5; --chain-border: #10b981;
  }
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto,
                 'Helvetica Neue', Arial, sans-serif;
    color: var(--fg); background: var(--bg); max-width: 960px;
    margin: 0 auto; padding: 2rem 1.5rem; line-height: 1.7; font-size: 15px;
  }
  h1 { font-size: 2rem; color: var(--heading); border-bottom: 3px solid var(--accent);
       padding-bottom: .5rem; margin-top: 0; }
  h2 { font-size: 1.5rem; color: var(--heading); border-bottom: 2px solid var(--border);
       padding-bottom: .3rem; margin-top: 2.5rem; }
  h3 { font-size: 1.2rem; color: var(--accent); margin-top: 2rem; }
  h4 { font-size: 1.05rem; color: var(--heading); margin-top: 1.5rem; }
  code {
    font-family: 'SFMono-Regular', Consolas, 'Liberation Mono', Menlo, monospace;
    font-size: 0.92em; background: var(--code-bg); padding: 0.15em 0.35em; border-radius: 3px;
  }
  pre {
    background: var(--code-bg); border: 1px solid var(--border); border-radius: 6px;
    padding: 1rem 1.2rem; overflow-x: auto; font-size: 0.88em; line-height: 1.55;
  }
  pre code { background: none; padding: 0; }
  table { border-collapse: collapse; width: 100%; margin: 1rem 0; font-size: 0.93em; }
  th, td { border: 1px solid var(--border); padding: 0.5rem 0.75rem;
            text-align: left; vertical-align: top; }
  th { background: var(--code-bg); font-weight: 600; }
  tr:nth-child(even) td { background: #fafafa; }
  .note, .warn, .chain-box {
    border-left: 4px solid; padding: 0.75rem 1rem; margin: 1.2rem 0;
    border-radius: 0 6px 6px 0;
  }
  .note    { background: var(--note-bg);  border-color: var(--note-border); }
  .warn    { background: var(--warn-bg);  border-color: var(--warn-border); }
  .chain-box { background: var(--chain-bg); border-color: var(--chain-border); }
  .toc { background: var(--code-bg); border: 1px solid var(--border);
         border-radius: 6px; padding: 1rem 1.5rem; margin: 1.5rem 0; }
  .toc ul, .toc ol { margin: 0.3rem 0; padding-left: 1.5rem; }
  .toc li { margin: 0.15rem 0; }
  .toc a { text-decoration: none; color: var(--accent); }
  .toc a:hover { text-decoration: underline; }
  a { color: var(--accent); }
  .file-path { font-weight: 600; color: var(--accent); }
  .func-sig  { font-family: monospace; font-size: 0.95em; font-weight: 600; }
  .diagram { text-align: center; margin: 1.5rem 0; }
  .diagram pre { display: inline-block; text-align: left; font-size: 0.82em; }
  .tag { display: inline-block; font-size: 0.78em; padding: 0.1em 0.5em;
         border-radius: 3px; font-weight: 600; vertical-align: middle; }
  .tag-static    { background: #dbeafe; color: #1e40af; }
  .tag-dynamic   { background: #fce7f3; color: #9d174d; }
  .tag-unchanged { background: #e5e7eb; color: #374151; }
  .tag-new       { background: #dcfce7; color: #166534; }
  hr { border: none; border-top: 1px solid var(--border); margin: 2.5rem 0; }"""

# ─── Inline rendering ─────────────────────────────────────────────────────────

def html_escape(s):
    return s.replace('&', '&amp;').replace('<', '&lt;').replace('>', '&gt;')

# Maps [tag] annotations in headings to coloured badge spans
TAG_BADGES = {
    '[static]':    '<span class="tag tag-static">static</span>',
    '[dynamic]':   '<span class="tag tag-dynamic">dynamic</span>',
    '[unchanged]': '<span class="tag tag-unchanged">unchanged</span>',
    '[new]':       '<span class="tag tag-new">new</span>',
}

def render_inline(text, filepath_h3=False):
    """Convert inline markdown to HTML.

    filepath_h3: when True, backtick spans whose content contains '/' or equals
    'Makefile' are rendered as <span class="file-path"> instead of <code>.
    """
    result = []
    i = 0
    n = len(text)
    while i < n:
        c = text[i]

        # Code span  `...`
        if c == '`':
            j = text.find('`', i + 1)
            if j != -1:
                content = text[i+1:j]
                if filepath_h3 and ('/' in content or content == 'Makefile'):
                    result.append('<span class="file-path">' + html_escape(content) + '</span>')
                else:
                    result.append('<code>' + html_escape(content) + '</code>')
                i = j + 1
                continue

        # Link  [text](url)
        if c == '[':
            m = re.match(r'\[([^\]]*)\]\(([^)]*)\)', text[i:])
            if m:
                result.append('<a href="' + html_escape(m.group(2)) + '">'
                              + render_inline(m.group(1)) + '</a>')
                i += len(m.group(0))
                continue

        # Bold  **text**
        if c == '*' and i + 1 < n and text[i+1] == '*':
            j = text.find('**', i + 2)
            if j != -1:
                result.append('<strong>' + render_inline(text[i+2:j]) + '</strong>')
                i = j + 2
                continue

        # Italic  *text*  (single asterisk)
        if c == '*' and (i + 1 >= n or text[i+1] != '*'):
            j = i + 1
            while j < n:
                if text[j] == '*' and (j + 1 >= n or text[j+1] != '*'):
                    break
                j += 1
            if j < n:
                result.append('<em>' + render_inline(text[i+1:j]) + '</em>')
                i = j + 1
                continue

        # HTML-escape special chars; pass everything else through
        result.append(html_escape(c) if c in '&<>' else c)
        i += 1
    return ''.join(result)


def render_heading_text(raw, level):
    """Render heading inner text: file-path spans (h3 only), inline markup, tag badges.

    Tag badges ([static], [new], etc.) are replaced after render_inline because
    render_inline outputs them as literal '[static]' text (no link match) and
    the replacement HTML must not be re-processed by the inline renderer.
    """
    html = render_inline(raw, filepath_h3=(level == 3))
    for marker, repl in TAG_BADGES.items():
        html = html.replace(marker, repl)
    return html


def slugify(text):
    """Generate a GitHub-style heading anchor from raw heading text."""
    t = re.sub(r'`([^`]*)`', r'\1', text)           # strip backticks, keep content
    t = re.sub(r'\*+([^*]*)\*+', r'\1', t)           # strip bold/italic markers
    t = re.sub(r'\[([^\]]*)\]\([^)]*\)', r'\1', t)   # strip links, keep text
    t = re.sub(r'!?\[[^\]]*\]', '', t)               # strip remaining [...] badges
    t = t.lower()
    t = re.sub(r'[^a-z0-9\s-]', '', t)
    t = t.strip().replace(' ', '-')
    return t


# ─── Table helpers ────────────────────────────────────────────────────────────

def parse_cells(line):
    # Protect escaped pipes (\|) from being treated as column separators
    line = line.replace('\\|', '\x00PIPE\x00')
    cells = [c.strip().replace('\x00PIPE\x00', '|') for c in line.split('|')]
    if cells and cells[0] == '':
        cells = cells[1:]
    if cells and cells[-1] == '':
        cells = cells[:-1]
    return cells

def is_separator_row(cells):
    return bool(cells) and all(re.match(r'^:?-+:?$', c) for c in cells)


# ─── Main renderer ────────────────────────────────────────────────────────────

def render(lines):
    out = []
    i = 0
    n = len(lines)

    # List stack: each entry is (indent_level, html_tag)
    list_stack = []

    # TOC nav state
    in_toc = False
    toc_has_items = False

    # Section 6 flag for func-sig on table first column
    func_sig_mode = False

    def flush_lists():
        while list_stack:
            _, tag = list_stack.pop()
            out.append(f'</{tag}>')

    def emit_list_item(indent, list_tag, content_html):
        # Close any lists that are deeper than current indent
        while list_stack and list_stack[-1][0] > indent:
            _, tag = list_stack.pop()
            out.append(f'</{tag}>')
        # Open a new list if needed
        if not list_stack or list_stack[-1][0] < indent:
            out.append(f'<{list_tag}>')
            list_stack.append((indent, list_tag))
        elif list_stack[-1][1] != list_tag:
            # Same indent, different type (ol <-> ul)
            out.append(f'</{list_stack[-1][1]}>')
            list_stack.pop()
            out.append(f'<{list_tag}>')
            list_stack.append((indent, list_tag))
        out.append(f'<li>{content_html}</li>')

    while i < n:
        line = lines[i].rstrip('\n')
        stripped = line.strip()

        # ── blank line ──────────────────────────────────────────────────────
        if not stripped:
            flush_lists()
            if in_toc and toc_has_items:
                out.append('</nav>')
                in_toc = False
                toc_has_items = False
            i += 1
            continue

        # ── horizontal rule ─────────────────────────────────────────────────
        if re.match(r'^-{3,}\s*$', line):
            flush_lists()
            if in_toc and toc_has_items:
                out.append('</nav>')
                in_toc = False
                toc_has_items = False
            out.append('<hr>')
            i += 1
            continue

        # ── fenced code block ────────────────────────────────────────────────
        if line.startswith('```'):
            flush_lists()
            lang = line[3:].strip()
            code_lines = []
            i += 1
            while i < n and not lines[i].rstrip('\n').startswith('```'):
                code_lines.append(html_escape(lines[i].rstrip('\n')))
                i += 1
            i += 1  # consume closing ```
            body = '\n'.join(code_lines)
            if lang == 'diagram':
                out.append(f'<div class="diagram"><pre>{body}</pre></div>')
            elif lang == 'flow':
                out.append(f'<div class="chain-box"><pre>{body}</pre></div>')
            else:
                out.append(f'<pre><code>{body}</code></pre>')
            continue

        # ── heading ──────────────────────────────────────────────────────────
        hm = re.match(r'^(#{1,4})\s+(.*)', line)
        if hm:
            flush_lists()
            if in_toc and toc_has_items:
                out.append('</nav>')
                in_toc = False
                toc_has_items = False
            level = len(hm.group(1))
            raw = hm.group(2).rstrip()
            slug = slugify(raw)
            inner = render_heading_text(raw, level)

            if level == 1:
                out.append(f'<h1 id="{slug}">{inner}</h1>')
            elif level == 2:
                sec_m = re.match(r'^(\d+)\.', raw)
                func_sig_mode = (int(sec_m.group(1)) == 6) if sec_m else False
                if raw.strip().lower() == 'contents':
                    out.append('<nav class="toc">\n<strong>Contents</strong>')
                    in_toc = True
                    toc_has_items = False
                else:
                    out.append(f'<h2 id="{slug}">{inner}</h2>')
            elif level == 3:
                out.append(f'<h3 id="{slug}">{inner}</h3>')
            else:
                out.append(f'<h4 id="{slug}">{inner}</h4>')
            i += 1
            continue

        # ── blockquote ───────────────────────────────────────────────────────
        if line.startswith('>'):
            flush_lists()
            bq_lines = []
            while i < n and lines[i].startswith('>'):
                bq_lines.append(lines[i].rstrip('\n'))
                i += 1
            first_content = bq_lines[0][1:].strip()
            if first_content == '[!NOTE]':
                cls, content_lines = 'note', bq_lines[1:]
            elif first_content == '[!WARNING]':
                cls, content_lines = 'warn', bq_lines[1:]
            else:
                cls, content_lines = 'blockquote', bq_lines
            tag = 'div' if cls in ('note', 'warn') else 'blockquote'
            attr = f' class="{cls}"' if cls in ('note', 'warn') else ''
            out.append(f'<{tag}{attr}>')
            in_bq_list = False
            for bl in content_lines:
                text = bl[1:].strip()
                if not text:
                    if in_bq_list:
                        out.append('</ul>')
                        in_bq_list = False
                    continue
                lm = re.match(r'^[-*]\s+(.*)', text)
                if lm:
                    if not in_bq_list:
                        out.append('<ul>')
                        in_bq_list = True
                    out.append(f'<li>{render_inline(lm.group(1))}</li>')
                else:
                    if in_bq_list:
                        out.append('</ul>')
                        in_bq_list = False
                    out.append(f'<p>{render_inline(text)}</p>')
            if in_bq_list:
                out.append('</ul>')
            out.append(f'</{tag}>')
            continue

        # ── table ────────────────────────────────────────────────────────────
        if '|' in line and i + 1 < n:
            next_stripped = lines[i+1].strip()
            if '|' in next_stripped and re.match(r'^[\|:\- ]+$', next_stripped):
                flush_lists()
                header_cells = parse_cells(line)
                i += 2  # skip header row + separator row
                out.append('<table>')
                out.append('<thead><tr>'
                           + ''.join(f'<th>{render_inline(c)}</th>' for c in header_cells)
                           + '</tr></thead><tbody>')
                while i < n:
                    row = lines[i].rstrip('\n')
                    if '|' not in row:
                        break
                    cells = parse_cells(row)
                    row_html = '<tr>'
                    for ci, cell in enumerate(cells):
                        cls = ' class="func-sig"' if (func_sig_mode and ci == 0) else ''
                        row_html += f'<td{cls}>{render_inline(cell)}</td>'
                    row_html += '</tr>'
                    out.append(row_html)
                    i += 1
                out.append('</tbody></table>')
                continue

        # ── list item ────────────────────────────────────────────────────────
        ul_m = re.match(r'^(\s*)([-*])\s+(.*)', line)
        ol_m = re.match(r'^(\s*)(\d+)\.\s+(.*)', line)
        lm = ul_m or ol_m
        if lm:
            indent = len(lm.group(1))
            list_tag = 'ul' if ul_m else 'ol'
            content = render_inline(lm.group(3))
            emit_list_item(indent, list_tag, content)
            if in_toc:
                toc_has_items = True
            i += 1
            continue

        # ── paragraph ────────────────────────────────────────────────────────
        flush_lists()
        para_lines = [stripped]
        i += 1
        while i < n:
            nxt = lines[i].rstrip('\n')
            nxt_stripped = nxt.strip()
            if not nxt_stripped:
                break
            if nxt_stripped.startswith(('`', '#', '>', '|')):
                break
            if nxt.startswith('```'):
                break
            if re.match(r'^(\s*)([-*]|\d+\.)\s', nxt):
                break
            if re.match(r'^-{3,}\s*$', nxt):
                break
            para_lines.append(nxt_stripped)
            i += 1
        # Join lines; trailing \ on a line means hard line break, else soft space join
        html_parts = []
        for idx, pl in enumerate(para_lines):
            has_break = pl.endswith('\\')
            html_parts.append(render_inline(pl[:-1] if has_break else pl))
            if idx < len(para_lines) - 1:
                html_parts.append('<br>' if has_break else ' ')
        out.append('<p>' + ''.join(html_parts) + '</p>')

    flush_lists()
    if in_toc:
        out.append('</nav>')

    return '\n'.join(out)


# ─── Entry point ──────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) != 2:
        print(f'Usage: {sys.argv[0]} <output.html>', file=sys.stderr)
        sys.exit(1)
    outfile = sys.argv[1]

    with open(README_PATH, encoding='utf-8') as f:
        lines = f.readlines()

    # Extract title from first h1
    title = 'mwan3 nftables Implementation'
    for line in lines:
        m = re.match(r'^# (.+)', line)
        if m:
            title = m.group(1).strip()
            break

    body = render(lines)

    html = (
        '<!DOCTYPE html>\n'
        '<html lang="en">\n'
        '<head>\n'
        '<meta charset="UTF-8">\n'
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">\n'
        f'<title>{html_escape(title)} - Developer Reference</title>\n'
        '<style>\n'
        f'{CSS}\n'
        '</style>\n'
        '</head>\n'
        '<body>\n\n'
        f'{body}\n\n'
        '</body>\n'
        '</html>\n'
    )

    with open(outfile, 'w', encoding='utf-8') as f:
        f.write(html)

    size = os.path.getsize(outfile)
    print(f'Written {size:,} bytes to {outfile}')


if __name__ == '__main__':
    main()
