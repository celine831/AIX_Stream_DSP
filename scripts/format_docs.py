"""Format existing project documents without rebuilding or rewriting their content."""
from pathlib import Path
from zipfile import ZipFile
from lxml import etree as E
import hashlib, json, re, shutil

ROOT = Path(__file__).resolve().parents[1]
W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
NS = {'w': W, 'm': 'http://schemas.openxmlformats.org/officeDocument/2006/math'}
CJK = re.compile(r'[\u3400-\u9fff\uf900-\ufaff]')
ASSISTANCE = re.compile(r'(?:借助|利用|使用|通过|由).{0,15}(?:\bAI\b|人工智能|大模型|ChatGPT|Codex)|(?:\bAI\b|ChatGPT|Codex).{0,12}(?:生成|辅助|协助|编写)', re.I)


def child(parent, name, first=False):
    node = parent.find('w:' + name, NS)
    if node is None:
        node = E.Element('{' + W + '}' + name)
        if first:
            parent.insert(0, node)
        else:
            parent.append(node)
    return node


def attr(element, name, value):
    element.set('{' + W + '}' + name, str(value))


def east_asia(rpr, font):
    fonts = child(rpr, 'rFonts', first=True)
    fonts.attrib.pop('{' + W + '}eastAsiaTheme', None)
    attr(fonts, 'eastAsia', font)


def paragraph_text(p):
    return ''.join(p.xpath('.//w:t/text()', namespaces=NS))


def heading(p, styles):
    sid = p.find('w:pPr/w:pStyle', NS)
    name = styles.get(sid.get('{' + W + '}val'), '') if sid is not None else ''
    if name.lower().startswith('heading') or name.lower() in ['title', 'subtitle', 'toc heading']:
        return True
    # Question prompts are short bold paragraphs rather than running body text.
    t = paragraph_text(p).strip()
    rs = [r for r in p.xpath('./w:r', namespaces=NS) if r.xpath('./w:t', namespaces=NS)]
    return bool(re.match(r'^\d+\s+\S', t) and rs and all(r.find('w:rPr/w:b', NS) is not None for r in rs))


def text_signature(data):
    output = {}
    for name, raw in data.items():
        if name.startswith('word/') and name.endswith('.xml'):
            try:
                xml = E.fromstring(raw)
            except E.XMLSyntaxError:
                continue
            # Include formulas, fields, hyperlinks, and textboxes in the preservation check.
            output[name] = xml.xpath('//w:t/text() | //m:t/text() | //w:instrText/text()', namespaces=NS)
    return output


def apply(file):
    original = file.read_bytes()
    backup = ROOT / 'tmp/doc_backups/font_spacing_before' / file.name
    backup.parent.mkdir(parents=True, exist_ok=True)
    if backup.exists() and backup.read_bytes() != original:
        backup = backup.with_name(backup.stem + '_' + hashlib.sha256(original).hexdigest()[:12] + backup.suffix)
    if not backup.exists():
        backup.write_bytes(original)
    with ZipFile(file) as z:
        info = z.infolist()
        data = {i.filename: z.read(i.filename) for i in info}
    before = text_signature(data)
    stylexml = E.fromstring(data['word/styles.xml'])
    styles = {}
    for s in stylexml.xpath('//w:style', namespaces=NS):
        n = s.find('w:name', NS)
        name = n.get('{' + W + '}val', '') if n is not None else ''
        styles[s.get('{' + W + '}styleId')] = name
        title = name.lower().startswith('heading') or name.lower() in ['title', 'subtitle', 'toc heading']
        east_asia(child(s, 'rPr'), '微软雅黑' if title else '宋体')
    defaults = child(child(stylexml, 'docDefaults', first=True), 'rPrDefault', first=True)
    east_asia(child(defaults, 'rPr'), '宋体')
    data['word/styles.xml'] = E.tostring(stylexml, xml_declaration=True, encoding='UTF-8', standalone=True)
    removed, formatted, fonts = [], 0, 0
    for name, raw in list(data.items()):
        if not (name.startswith('word/') and name.endswith('.xml')) or name == 'word/styles.xml':
            continue
        xml = E.fromstring(raw)
        modified = False
        for para in list(xml.xpath('//w:p', namespaces=NS)):
            text = paragraph_text(para)
            if ASSISTANCE.search(text):
                removed.append(text)
                para.getparent().remove(para)
                modified = True
                continue
            is_heading = heading(para, styles)
            for r in para.xpath('.//w:r', namespaces=NS):
                if CJK.search(''.join(r.xpath('./w:t/text()', namespaces=NS))):
                    east_asia(child(r, 'rPr', first=True), '微软雅黑' if is_heading else '宋体')
                    fonts += 1
                    modified = True
            if is_heading and name == 'word/document.xml':
                # Compact heading spacing prevents short continuation pages after
                # increasing prose to 1.5 lines, without changing font sizes.
                pr = child(para, 'pPr', first=True)
                spacing = child(pr, 'spacing')
                attr(spacing, 'before', 160)
                attr(spacing, 'after', 80)
                modified = True
            if name == 'word/document.xml' and para.xpath('ancestor::w:tbl', namespaces=NS):
                spacing = child(child(para, 'pPr', first=True), 'spacing')
                attr(spacing, 'before', 40)
                attr(spacing, 'after', 40)
                modified = True
            if (name == 'word/document.xml' and not text.strip()
                    and not para.xpath('.//w:drawing | .//m:oMath | .//w:br[@w:type="page"]', namespaces=NS)):
                spacing = child(child(para, 'pPr', first=True), 'spacing')
                attr(spacing, 'before', 0)
                attr(spacing, 'after', 0)
                attr(spacing, 'line', 120)
                attr(spacing, 'lineRule', 'auto')
                modified = True
            # Tables, titles, figure/formula-only paragraphs and document metadata
            # retain their layout; only ordinary prose and Q&A answers get indentation.
            is_body = (name == 'word/document.xml' and text.strip() and not is_heading
                       and not para.xpath('ancestor::w:tbl', namespaces=NS)
                       and not re.match(r'^\s*(?:版本|目标器件)\b', text)
                       and not para.xpath('.//w:drawing | .//m:oMath', namespaces=NS))
            if is_body:
                pr = child(para, 'pPr', first=True)
                spacing = child(pr, 'spacing')
                attr(spacing, 'line', 360)
                attr(spacing, 'lineRule', 'auto')
                attr(spacing, 'before', 0)
                attr(spacing, 'after', 0)
                ind = child(pr, 'ind')
                for key in ['hanging', 'hangingChars']:
                    ind.attrib.pop('{' + W + '}' + key, None)
                attr(ind, 'firstLineChars', 200)
                # 22 pt is a compatible fallback for the existing 11 pt body style.
                attr(ind, 'firstLine', 440)
                grid = child(pr, 'snapToGrid')
                attr(grid, 'val', 0)
                attr(child(pr, 'keepLines'), 'val', 1)
                # Retain original paragraph spacing, but put edited properties in
                # the WordprocessingML schema order for Word and WPS compatibility.
                order = ['pStyle','keepNext','keepLines','pageBreakBefore','framePr','widowControl',
                         'numPr','suppressLineNumbers','pBdr','shd','tabs','suppressAutoHyphens',
                         'kinsoku','wordWrap','overflowPunct','topLinePunct','autoSpaceDE','autoSpaceDN',
                         'bidi','adjustRightInd','snapToGrid','spacing','ind','contextualSpacing',
                         'mirrorIndents','suppressOverlap','jc','textDirection','textAlignment',
                         'textboxTightWrap','outlineLvl','divId','cnfStyle','rPr','sectPr','pPrChange']
                ranked = {key: i for i, key in enumerate(order)}
                for e in sorted(list(pr), key=lambda e: ranked.get(E.QName(e).localname, 100)):
                    pr.remove(e); pr.append(e)
                formatted += 1
                modified = True
        if modified:
            data[name] = E.tostring(xml, xml_declaration=True, encoding='UTF-8', standalone=True)
    after = text_signature(data)
    if not removed:
        assert before == after, 'Formatting changed document text'
    unchanged = [name for name in data if not (name.startswith('word/') and name.endswith('.xml'))]
    staged = ROOT / 'tmp/doc_qa/font_spacing' / file.name
    staged.parent.mkdir(parents=True, exist_ok=True)
    with ZipFile(staged, 'w') as z:
        for i in info:
            z.writestr(i, data[i.filename])
    with ZipFile(staged) as z:
        assert z.testzip() is None
        for name in unchanged:
            assert z.read(name) == data[name]
    try:
        staged.replace(file)
        output = file
    except PermissionError:
        output = file.with_name(file.stem + '_排版版.docx')
        shutil.copyfile(staged, output)
    return {'path':str(output.relative_to(ROOT)), 'body_paragraphs':formatted, 'chinese_runs':fonts,
            'text_unchanged':not removed, 'removed_assistance_statements':removed,
            'before_sha256':hashlib.sha256(original).hexdigest(),
            'sha256':hashlib.sha256(output.read_bytes()).hexdigest()}


if __name__ == '__main__':
    files = [ROOT/'doc/01_项目设计说明书.docx', ROOT/'doc/02_模块实现与验证报告.docx']
    results = [apply(f) for f in files]
    (ROOT/'tmp/doc_qa/font_spacing/format_check.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
    print(json.dumps(results,ensure_ascii=True,indent=2))
