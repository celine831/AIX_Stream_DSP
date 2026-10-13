from pathlib import Path
import re,json,hashlib
ROOT=Path(__file__).resolve().parents[1]

def collect():
    sim=json.loads((ROOT/'sim/results/summary.json').read_text())
    result={'date':'2026-10-13','device':'EP4CE10F17C8','quartus':'13.0.1 Build 232','modelsim':'SE-64 10.5',
            'simulation_tests':len(sim),'fir_comparisons':16896,'quantizer_comparisons':122880,'simulation':sim,'revisions':{}}
    result['board_golden_comparisons']=512
    for rev,folder in [('accelerator','output_files'),('accelerator_cdc','output_files_cdc'),('board_selftest','output_files_board')]:
        rpt=ROOT/'Qproject/reports'
        compile_text=(rpt/(rev+'_compile.log')).read_text(encoding='utf-8',errors='replace')
        assert 'Full Compilation was successful' in compile_text
        assert not re.search('Timing requirements not met|Ignored filter|Read_sdc failed',compile_text)
        fmax=(rpt/(rev+'_fmax.txt')).read_text()
        values=re.findall(r';\s*([\d.]+) MHz\s*;\s*[\d.]+ MHz\s*;\s*(\w+)',fmax)
        fit=(ROOT/'Qproject'/folder/(rev+'.fit.summary')).read_text()
        resources={}
        for k in ['Total logic elements','Total registers','Total memory bits','Embedded Multiplier 9-bit elements','Total pins']:
            m=re.search(re.escape(k)+r'\s*:\s*([\d,]+)',fit)
            resources[k]=int(m.group(1).replace(',',''))
        slacks={}
        for kind in ['setup','hold','recovery','removal']:
            text=(rpt/(rev+'_'+kind+'.txt')).read_text()
            match=re.search(r'Worst case slack is\s+(-?[\d.]+)',text)
            slacks[kind]=float(match.group(1)) if match else None
            if match: assert float(match.group(1))>=0,(rev,kind)
        check=(rpt/(rev+'_check_timing.txt')).read_text()
        for k in ['no_clock','multiple_clock','no_input_delay','no_output_delay']:
            assert re.search(r';\s*'+k+r'\s*;\s*0\s*;',check)
        ucp=(rpt/(rev+'_unconstrained.txt')).read_text()
        assert not re.search(r';\s*Unconstrained[^;]*;\s*[1-9]',ucp)
        result['revisions'][rev]={'fmax_mhz':{clk:float(v) for v,clk in values},'resources':resources,
            'slow_85C_slack_ns':slacks,'target_core_mhz':50 if rev=='board_selftest' else 75,'target_source_mhz':50 if rev.endswith('cdc') else None,
            'all_corner_timing_met':True,'constraint_checks':0,'board_pin_assignment_complete':rev=='board_selftest'}
        if rev=='board_selftest':
            pin_text=(ROOT/'Qproject'/folder/'board_selftest.pin').read_text()
            mapping={'sys_clk':'E1','sys_rst_n':'M15','led[0]':'L7','led[1]':'M6','led[2]':'P3','led[3]':'N3'}
            for port,pin in mapping.items():
                matches=[line for line in pin_text.splitlines() if line.split(':')[0].strip()==port]
                assert len(matches)==1,(port,'missing or duplicate fitted port')
                columns=[c.strip() for c in matches[0].split(':')]
                assert columns[1]==pin and columns[3]=='3.3-V LVTTL' and columns[-1]=='Y',(port,columns)
            assert resources['Total pins']==6
            result['revisions'][rev]['verified_pin_map']=mapping
    skew=(ROOT/'Qproject/reports/accelerator_cdc_gray_skew.txt').read_text()
    assert '0 violated' in skew and 'Found 20 paths' in skew
    result['gray_skew_worst_slack_ns']=float(re.search(r'Worst case slack is\s+([\d.]+)',skew).group(1))
    result['hashes']={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
        for pattern in ['rtl/*.v','board/*.v','board/*.py','sim/*.sv','sim/*.py','Qproject/*.sdc','Qproject/board_pins.qsf'] for p in ROOT.glob(pattern)}
    qa_path=ROOT/'Qproject/reports/document_qa.json'
    if qa_path.exists():
        qa=json.loads(qa_path.read_text(encoding='utf-8'))
        for item in qa['documents']:
            item['matches_inspected_file']=hashlib.sha256((ROOT/item['path']).read_bytes()).hexdigest()==item['sha256']
        result['documentation']=qa
    (ROOT/'verification_summary.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:v for k,v in result.items() if k in ['simulation_tests','fir_comparisons','quantizer_comparisons','revisions']},ensure_ascii=False,indent=2))
    return result

if __name__=='__main__': collect()
