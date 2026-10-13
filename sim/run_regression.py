"""Run with Python; uses locally installed ModelSim. All logs kept in sim/results."""
from pathlib import Path
import argparse, json, os, subprocess, sys
from golden_model import CASES, generate

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--modelsim-bin',default=os.environ.get('MODELSIM_BIN',r'D:\00study\01fpga\DownloadSoftware\modelsim_se\win64'))
    a=ap.parse_args()
    root=Path(__file__).resolve().parent
    os.chdir(root)
    result=root/'results'; result.mkdir(exist_ok=True)
    binaries=Path(a.modelsim_bin)
    def invoke(tool,args,log):
        proc=subprocess.run([str(binaries/(tool+'.exe')),*args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,errors='replace',cwd=root)
        (result/log).write_text(proc.stdout,encoding='utf-8')
        if proc.returncode: print(proc.stdout); raise RuntimeError(f'{tool} returned {proc.returncode}')
        return proc.stdout
    generate()
    if not (root/'work').exists(): invoke('vlib',['work'],'vlib.log')
    invoke('vmap',['work','work'],'vmap.log')
    subprocess.run([sys.executable,str(root.parent/'board/generate_board_vectors.py')],check=True)
    sources=[str(p) for p in (root.parent/'rtl').glob('*.v')]+[str(root.parent/'board/board_vectors.v')]
    compiled=invoke('vlog',['-lint',*sources],'compile_rtl_verilog2001.log')
    compiled+=invoke('vlog',['-sv','-lint','tb_accelerator.sv','tb_quantizer.sv','tb_fifo.sv','tb_board_selftest.sv'],'compile_testbench.log')
    (result/'compile_lint.log').write_text(compiled,encoding='utf-8')
    if '** Warning:' in compiled or '** Error:' in compiled: raise RuntimeError('Resolve compiler lint diagnostics before accepting regression')
    summary=[]
    names=dict(dw='DATA_WIDTH',cw='COEFF_WIDTH',ow='OUT_WIDTH',taps='TAPS',shift='SHIFT',round='ROUND_MODE',sat='SATURATE',frame='FRAME_RESET',cdc='USE_ASYNC',fa='FIFO_ADDR_WIDTH',src='SOURCE_HALF_PERIOD')
    for c in CASES:
        params=[f'-g{names[k]}={v}' for k,v in c.items() if k!='name']
        out=invoke('vsim',['-c','-voptargs=+acc',*params,'work.tb_accelerator','+CASE='+c['name'],'-wlf',str(result/(c['name']+'.wlf')),'-do','onerror {quit -code 1 -force}; onbreak {quit -code 1 -force}; log -r /*; run -all; quit -code 0 -force'],c['name']+'.log')
        passes=[line for line in out.splitlines() if 'PASS case=' in line]
        if len(passes)!=1 or '** Fatal:' in out: raise RuntimeError(c['name']+' failed: '+out)
        print(passes[0]); summary.append(dict(case=c['name'],status='PASS',evidence=passes[0]))
    for shift in [0,1,3,7,11]:
        out=invoke('vsim',['-c',f'-gSHIFT={shift}','work.tb_quantizer','-do','onerror {quit -code 1 -force}; onbreak {quit -code 1 -force}; run -all; quit -code 0 -force'],f'quantizer_{shift}.log')
        if 'PASS quantizer' not in out: raise RuntimeError(out)
        print(next(l for l in out.splitlines() if 'PASS quantizer' in l))
        summary.append(dict(case=f'quantizer_shift{shift}',status='PASS',checks=4096*6))
    out=invoke('vsim',['-c','work.tb_fifo','-do','onerror {quit -code 1 -force}; onbreak {quit -code 1 -force}; run -all; quit -code 0 -force'],'fifo.log')
    if 'PASS fifo' not in out: raise RuntimeError(out)
    summary.append(dict(case='fifo_full_pop_push',status='PASS'))
    out=invoke('vsim',['-c','-voptargs=+acc','work.tb_board_selftest','-wlf',str(result/'board_selftest.wlf'),'-do','onerror {quit -code 1 -force}; onbreak {quit -code 1 -force}; log -r /*; run -all; quit -code 0 -force'],'board_selftest.log')
    if 'PASS board_selftest' not in out or '** Fatal:' in out: raise RuntimeError(out)
    print(next(l for l in out.splitlines() if 'PASS board_selftest' in l))
    summary.append(dict(case='board_selftest',status='PASS',checks=512))
    (result/'summary.json').write_text(json.dumps(summary,indent=2)+'\n')
    print(f'PASS {len(summary)} tests; FIR comparisons={len(CASES)*1536}; quantizer comparisons=122880')

if __name__=='__main__': main()
