"""Validate the bundled mesh and optionally render a top-down inspection image.

python scripts/validate_zurich_city.py [preview.png]  (preview needs Pillow)
"""
import collections, json, math, pathlib, sys

path=pathlib.Path(__file__).resolve().parents[1]/'native/Takt/Resources/zurich-city.json'
d=json.loads(path.read_bytes())
assert d['cityID']=='zurich'
assert len(d['tiles'])>70
assert d['statistics']['buildingPolygons']>40000
assert d['sourceCounts']['av_bo_boflaeche_a']==107638
assert d['bounds'][2]-d['bounds'][0]>130 and d['bounds'][3]-d['bounds'][1]>120
counts=collections.Counter()
for t in d['tiles']:
    for m in t['meshes']:
        p,i=m['positions'],m['indices']
        assert len(p)%3==0 and len(i)%3==0
        assert min(i)>=0 and max(i)<len(p)//3
        assert all(math.isfinite(v) for v in p)
        counts[m['kind']]+=len(i)//3
        if not m['kind'].startswith('building'):
            for a,b,c in zip(i[::3],i[1::3],i[2::3]):
                ax,az=p[a*3],p[a*3+2]; bx,bz=p[b*3],p[b*3+2]; cx,cz=p[c*3],p[c*3+2]
                assert (bx-ax)*(cz-az)-(bz-az)*(cx-ax) <= 1e-10
print('Validated',len(d['tiles']),'tiles;',path.stat().st_size,'bytes;',dict(counts))
if len(sys.argv)>1:
    from PIL import Image,ImageDraw
    im=Image.new('RGB',(1600,1600),'#c5cbb2'); draw=ImageDraw.Draw(im)
    palette=dict(water='#528f9c',park='#b1c196',forest='#678a68',road='#e8e0ca',roof='#927b68')
    xmin,zmin,xmax,zmax=d['bounds']; scale=1500/max(xmax-xmin,zmax-zmin)
    for kind in palette:
        for t in d['tiles']:
            for m in t['meshes']:
                if m['kind']!=kind: continue
                p=m['positions']; inds=m['indices']
                pts=[(50+(x-xmin)*scale,50+(z-zmin)*scale) for x,z in zip(p[::3],p[2::3])]
                for a,b,c in zip(inds[::3],inds[1::3],inds[2::3]):
                    draw.polygon([pts[a],pts[b],pts[c]],fill=palette[kind])
    im.save(sys.argv[1])
    print('Preview',sys.argv[1])
