#!/usr/bin/env python3
"""
Builds docs/IEEE_Phase2_Project_Report.pdf (and .html) from the Markdown report.
Needs:  pip install markdown playwright   (and `python -m playwright install chromium` once)
Run from the repo root:  python3 docs/build_report_pdf.py   [--html-only | --pdf-only]
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "IEEE_Phase2_Project_Report.md")
HTML = os.path.join(HERE, "IEEE_Phase2_Project_Report.html")
PDF = os.path.join(HERE, "IEEE_Phase2_Project_Report.pdf")

CSS = """
@page { size: A4; margin: 18mm 16mm 18mm 16mm; }
body { font-family: 'Times New Roman', Times, serif; font-size: 10.5pt; line-height: 1.38; color: #111; }
h1 { font-size: 17pt; text-align: center; margin: 0 0 10pt; line-height: 1.2; }
h2 { font-size: 12.5pt; margin: 16pt 0 6pt; border-bottom: 1px solid #999; padding-bottom: 2pt; }
h3 { font-size: 11pt; margin: 11pt 0 4pt; font-style: italic; }
p, li { text-align: justify; }
table { border-collapse: collapse; width: 100%; margin: 8pt 0; font-size: 9pt; page-break-inside: avoid; }
th, td { border: 1px solid #888; padding: 3pt 5pt; vertical-align: top; text-align: left; }
th { background: #eee; }
img { max-width: 100%; display: block; margin: 8pt auto 2pt; page-break-inside: avoid; }
p.caption { text-align: center; font-size: 9pt; color: #333; }
code { font-family: Menlo, Consolas, monospace; font-size: 8.8pt; background: #f3f3f3; padding: 0 2px; }
hr { border: 0; border-top: 1px solid #bbb; margin: 12pt 0; }
"""


def build_html():
    import markdown
    body = markdown.markdown(open(SRC, encoding="utf-8").read(), extensions=["tables", "sane_lists"])
    body = body.replace("<p><em>Fig.", '<p class="caption"><em>Fig.')   # figure captions
    html = f"<!doctype html><html><head><meta charset='utf-8'><title>ProtocolX Phase II Report</title><style>{CSS}</style></head><body>{body}</body></html>"
    open(HTML, "w", encoding="utf-8").write(html)
    print("wrote", HTML)


def build_pdf():
    from playwright.sync_api import sync_playwright
    with sync_playwright() as p:
        b = p.chromium.launch()
        pg = b.new_page()
        pg.goto("file://" + HTML)
        pg.wait_for_load_state("load")
        pg.pdf(path=PDF, format="A4", print_background=True,
               display_header_footer=True, header_template="<span></span>",
               footer_template="<div style='font-size:8pt;width:100%;text-align:center;color:#666'>"
                               "ProtocolX — Phase II Report — <span class='pageNumber'></span> / <span class='totalPages'></span></div>",
               margin={"top": "18mm", "bottom": "18mm", "left": "16mm", "right": "16mm"})
        b.close()
    print("wrote", PDF)


if __name__ == "__main__":
    # --html-only / --pdf-only let the two halves run in different Python
    # environments (e.g. markdown in one venv, a working Playwright in another).
    if "--pdf-only" not in sys.argv:
        build_html()
    if "--html-only" not in sys.argv:
        build_pdf()
