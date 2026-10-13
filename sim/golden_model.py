"""Independent integer FIR reference. No floating point or RTL-width mimicry."""
from pathlib import Path
import json
import random

CASES = [
    dict(name='sync_default', dw=16,cw=16,ow=16,taps=8,shift=15,round=1,sat=1,frame=0,cdc=0,fa=4),
    dict(name='async_default',dw=16,cw=16,ow=16,taps=8,shift=15,round=1,sat=1,frame=0,cdc=1,fa=4),
    dict(name='odd_taps_even',dw=12,cw=10,ow=10,taps=3,shift=7,round=2,sat=1,frame=1,cdc=0,fa=2),
    dict(name='async_wrap',dw=8,cw=8,ow=8,taps=5,shift=4,round=0,sat=0,frame=1,cdc=1,fa=2),
    dict(name='one_tap_shift0',dw=8,cw=8,ow=8,taps=1,shift=0,round=1,sat=1,frame=0,cdc=0,fa=2),
    dict(name='sixteen_taps',dw=16,cw=12,ow=16,taps=16,shift=11,round=2,sat=1,frame=0,cdc=1,fa=3),
    dict(name='trunc_sat',dw=8,cw=8,ow=8,taps=3,shift=3,round=0,sat=1,frame=0,cdc=0,fa=2),
    dict(name='round_wrap',dw=8,cw=8,ow=8,taps=3,shift=3,round=1,sat=0,frame=0,cdc=1,fa=2),
    dict(name='even_wrap',dw=8,cw=8,ow=8,taps=1,shift=1,round=2,sat=0,frame=1,cdc=1,fa=2),
    dict(name='away_ties',dw=8,cw=8,ow=8,taps=1,shift=1,round=1,sat=1,frame=0,cdc=0,fa=2),
    dict(name='async_fast_source',dw=16,cw=16,ow=16,taps=8,shift=15,round=1,sat=1,frame=0,cdc=1,fa=4,src=3),
]

def quantize(value, width, shift, rounding, saturate):
    if rounding == 0:
        result = value // (1 << shift)
    else:
        q, r = divmod(abs(value), 1 << shift)
        if shift and (2*r > 1 << shift or (2*r == 1 << shift and (rounding == 1 or q % 2))):
            q += 1
        result = -q if value < 0 else q
    if saturate:
        return max(-(1 << (width-1)), min((1 << (width-1))-1, result))
    return (result + (1 << (width-1))) % (1 << width) - (1 << (width-1))

def generate():
    folder = Path(__file__).parent / 'vectors'
    folder.mkdir(exist_ok=True)
    for idx,c in enumerate(CASES):
        rng=random.Random(20261013+idx)
        hi=(1 << (c['dw']-1))-1; lo=-(1 << (c['dw']-1))
        chi=(1 << (c['cw']-1))-1; clo=-(1 << (c['cw']-1))
        phases=[[1]+[0]*(c['taps']-1),
                [chi if i%2==0 else clo for i in range(c['taps'])],
                [rng.randint(clo,chi) for _ in range(c['taps'])]]
        coeff=[]; lines=[]
        for phase,cs in enumerate(phases):
            coeff.extend(str(v) for v in cs)
            hist=[0]*c['taps']
            xs=[0,1,-1,3,-3,5,-5,hi,lo,hi,lo]+[0]*c['taps']+[hi]*32+[lo]*32
            xs += [rng.randint(lo,hi) for _ in range(512-len(xs))]
            for j,x in enumerate(xs):
                last=int(j%37==36 or j==len(xs)-1)
                hist=[x]+hist[:-1]
                acc=sum(a*b for a,b in zip(hist,cs))
                y=quantize(acc,c['ow'],c['shift'],c['round'],c['sat'])
                lines.append(f'{x} {y} {last}')
                if last and c['frame']: hist=[0]*c['taps']
        (folder/(c['name']+'_coeff.txt')).write_text('\n'.join(coeff)+'\n')
        (folder/(c['name']+'_data.txt')).write_text('\n'.join(lines)+'\n')
    (folder/'manifest.json').write_text(json.dumps(CASES,indent=2)+'\n')
    print(f'Generated {len(CASES)} cases, {len(CASES)*1536} FIR expected outputs')

if __name__=='__main__':
    assert quantize(-3,8,1,1,1)==-2
    assert quantize(-5,8,1,2,1)==-2
    assert quantize(5,8,1,2,1)==2
    assert quantize(-1,8,1,0,1)==-1
    generate()
