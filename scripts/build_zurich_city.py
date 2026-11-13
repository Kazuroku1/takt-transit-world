"""Build the offline Zurich mesh from the municipal CCZero cadastral WFS.

python -m pip install shapely pyproj numpy mapbox-earcut
python scripts/build_zurich_city.py
Raw downloads are cached outside the repository. No service is used at runtime.
"""
from __future__ import annotations
import collections, datetime, hashlib, json, math, os, pathlib, re, tempfile
import urllib.parse, urllib.request
from concurrent.futures import ThreadPoolExecutor
import numpy as np
import mapbox_earcut
from pyproj import Transformer
from shapely import make_valid
from shapely.geometry import shape, Polygon, box
from shapely.ops import transform, unary_union
from shapely.geometry.polygon import orient

ROOT = pathlib.Path(__file__).resolve().parents[1]
CACHE = pathlib.Path(tempfile.gettempdir()) / 'takt-zurich-wfs-v1'
CACHE.mkdir(exist_ok=True)
WFS = 'https://www.ogd.stadt-zuerich.ch/wfs/geoportal/Amtliche_Vermessung_Stadt_Zuerich'
LAYERS = ['av_bo_allegebaeude_a_v', 'av_bo_boflaeche_a', 'av_ge_gemeindegrenze_a', 'av_geb_strassenstueck']
TILE = 12.0
CX, CY = Transformer.from_crs(4326,2056,always_xy=True).transform(8.5417,47.3769)

def request(params):
    return urllib.request.urlopen(WFS+'?'+urllib.parse.urlencode(dict(service='WFS',version='1.1.0',**params)), timeout=600).read()

def download(layer):
    count = int(re.search(rb'numberOfFeatures="(\d+)"', request(dict(request='GetFeature',typeName=layer,resultType='hits')))[1])
    path = CACHE / (layer+'.json')
    if not path.exists():
        print('Downloading',layer,count,flush=True)
        fields = 'geometry,art_txt,status_txt' if layer in LAYERS[:2] else 'geometry'
        data = request(dict(request='GetFeature',typeName=layer,outputFormat='GeoJSON',srsName='EPSG:2056',maxFeatures=count+1,propertyName=fields))
        json.loads(data)
        path.write_bytes(data)
    data=json.loads(path.read_bytes())
    assert len(data['features']) == count, (layer,count,len(data['features']))
    print('Verified complete layer',layer,count,flush=True)
    return layer,data['features']

def polygons(geom):
    if geom.is_empty: return
    if geom.geom_type == 'Polygon': yield geom
    elif hasattr(geom,'geoms'):
        for g in geom.geoms: yield from polygons(g)

def local(geom):
    return transform(lambda x,y,z=None: ((np.asarray(x)-CX)/100,(CY-np.asarray(y))/100),geom)

tiles = {}
stats=collections.Counter()

def mesh_for(tx,tz,kind):
    tile=tiles.setdefault((tx,tz),dict(id=f'{tx}:{tz}',bounds=[tx*TILE,tz*TILE,(tx+1)*TILE,(tz+1)*TILE],meshes={}))
    return tile['meshes'].setdefault(kind,dict(kind=kind,positions=[],indices=[]))

def add_surface(mesh,poly,y):
    rings = [list(poly.exterior.coords)[:-1]]+[list(r.coords)[:-1] for r in poly.interiors]
    rings=[r for r in rings if len(r)>=3]
    verts=np.array([v for r in rings for v in r],dtype=np.float64)
    ends=np.cumsum([len(r) for r in rings],dtype=np.uint32)
    inds=mapbox_earcut.triangulate_float64(verts,ends).reshape(-1,3)
    # Earcut is x/z, so reverse winding where necessary to face +Y.
    a,b,c=verts[inds[:,0]],verts[inds[:,1]],verts[inds[:,2]]
    signed=(b[:,0]-a[:,0])*(c[:,1]-a[:,1])-(b[:,1]-a[:,1])*(c[:,0]-a[:,0])
    inds[signed>0]=inds[signed>0][:,[0,2,1]]
    triangle_area=float(np.abs(signed).sum()/2)
    assert abs(triangle_area-poly.area) < max(1e-6,poly.area*1e-6), ('triangulation area',triangle_area,poly.area)
    # Quantization can reverse very thin slivers. Keep final winding up-facing.
    quantized=np.round(verts,3)
    a,b,c=quantized[inds[:,0]],quantized[inds[:,1]],quantized[inds[:,2]]
    signed=(b[:,0]-a[:,0])*(c[:,1]-a[:,1])-(b[:,1]-a[:,1])*(c[:,0]-a[:,0])
    inds[signed>0]=inds[signed>0][:,[0,2,1]]
    offset=len(mesh['positions'])//3
    mesh['positions'].extend(v for x,z in verts for v in (round(x,3),round(y,3),round(z,3)))
    mesh['indices'].extend((inds.reshape(-1)+offset).tolist())
    stats['triangles']+=len(inds)
    stats['holes']+=len(poly.interiors)

def add_walls(mesh,poly,height):
    # Orient outer ring CCW and inner rings CW in x/z. Each quad has dedicated
    # vertices so renderer-generated normals keep corners crisp.
    poly=orient(poly,1)
    for ring in [poly.exterior,*poly.interiors]:
        pts=list(ring.coords)
        for (x,z),(xx,zz) in zip(pts,pts[1:]):
            offset=len(mesh['positions'])//3
            mesh['positions'].extend(round(v,3) for v in [x,.025,z,xx,.025,zz,xx,height,zz,x,height,z])
            mesh['indices'].extend(offset+i for i in [0,2,1,0,3,2])
            stats['triangles']+=2

def surface(poly,kind,y):
    minx,minz,maxx,maxz=poly.bounds
    for tx in range(math.floor(minx/TILE),math.floor(maxx/TILE)+1):
        for tz in range(math.floor(minz/TILE),math.floor(maxz/TILE)+1):
            clipped=poly.intersection(box(tx*TILE,tz*TILE,(tx+1)*TILE,(tz+1)*TILE))
            for part in polygons(clipped):
                if part.area>0.00001: add_surface(mesh_for(tx,tz,kind),part,y)

def main():
    layers=dict(ThreadPoolExecutor(max_workers=3).map(download,LAYERS))
    boundary=local(make_valid(unary_union([shape(f['geometry']) for f in layers[LAYERS[2]]])))
    bounds=list(boundary.bounds)
    print('Boundary',bounds,flush=True)
    classes=collections.Counter(f['properties'].get('art_txt','') for f in layers[LAYERS[1]])
    print('Landcover classes',dict(classes),flush=True)
    for n,f in enumerate(layers[LAYERS[1]]):
        kindtext=f['properties'].get('art_txt','').lower()
        if 'gewaesser' in kindtext or 'gewässer' in kindtext: kind,y='water',.008
        elif 'bestockt' in kindtext: kind,y='forest',.012
        elif 'humusiert' in kindtext: kind,y='park',.01
        elif 'strasse' in kindtext or 'weg' in kindtext or 'bahn' in kindtext: kind,y='road',.019
        else: continue
        geom=local(make_valid(shape(f['geometry']))).simplify(.018,preserve_topology=True)
        for poly in polygons(geom):
            if poly.area>.0004: surface(poly,kind,y)
        stats[kind+'Features']+=1
        if n%10000==0: print('Landcover',n,flush=True)
    for n,f in enumerate(layers[LAYERS[0]]):
        if f['properties'].get('status_txt') not in (None,'real'): stats['nonRealBuildingsSkipped']+=1; continue
        geom=local(make_valid(shape(f['geometry']))).simplify(.007,preserve_topology=True)
        seed=int(hashlib.sha256(f['id'].encode()).hexdigest()[:8],16)
        for poly in polygons(geom):
            if poly.area<.0004: stats['tinyBuildingsSkipped']+=1; continue
            x,z=poly.representative_point().coords[0]; tx,tz=math.floor(x/TILE),math.floor(z/TILE)
            area=poly.area*10000
            # Deliberately illustrative heights, NOT survey heights.
            height=(4+seed%3 if area<70 else 9+seed%12 if area<700 else 13+seed%15)/100
            add_surface(mesh_for(tx,tz,'roof'),poly,height)
            add_walls(mesh_for(tx,tz,['building','building2','building3'][seed%3]),poly,height)
            stats['buildingPolygons']+=1
        if n%10000==0: print('Buildings',n,flush=True)
    labels=[]
    for name,lon,lat in [('Altstadt',8.543,47.372),('Altstetten',8.488,47.391),('Oerlikon',8.545,47.410),('Wollishofen',8.533,47.341),('Wiedikon',8.516,47.365),('Enge',8.529,47.356),('Seefeld',8.558,47.356),('Höngg',8.497,47.402),('Schwamendingen',8.574,47.405),('Affoltern',8.510,47.421),('Wipkingen',8.526,47.396),('Fluntern',8.570,47.384),('Albisrieden',8.484,47.374)]:
        xx,yy=Transformer.from_crs(4326,2056,always_xy=True).transform(lon,lat)
        labels.append(dict(name=name,x=round((xx-CX)/100,3),z=round((CY-yy)/100,3)))
    for tile in tiles.values():
        tile['meshes']=list(tile['meshes'].values())
        # Buildings can extend beyond nominal tile bounds; include actual bounds.
        points=[m['positions'] for m in tile['meshes']]
        tile['bounds']=[min(min(p[0::3]) for p in points),min(min(p[2::3]) for p in points),max(max(p[0::3]) for p in points),max(max(p[2::3]) for p in points)]
        for m in tile['meshes']:
            assert len(m['positions'])%3==0 and len(m['indices'])%3==0
            assert max(m['indices']) < len(m['positions'])//3
            assert all(math.isfinite(p) for p in m['positions'])
    stats['tiles']=len(tiles)
    stats['meshes']=sum(len(t['meshes']) for t in tiles.values())
    data=dict(version=1,cityID='zurich',center=[8.5417,47.3769],metersPerUnit=100,bounds=bounds,
        attribution='Stadt Zürich, Geomatik + Vermessung — Amtliche Vermessung, CCZero',
        heightNote='Gebäudehöhen gestalterisch angenähert, nicht vermessen. Flaches Gelände.',
        sourceDate=datetime.date.today().isoformat(),sourceCounts={k:len(v) for k,v in layers.items()},statistics=dict(stats),
        boundary=[[[round(x,3),round(z,3)] for x,z in p.exterior.coords] for p in polygons(boundary.simplify(.025))],
        labels=labels,tiles=list(tiles.values()))
    path=ROOT/'native/Takt/Resources/zurich-city.json'
    path.parent.mkdir(parents=True,exist_ok=True)
    temporary=path.with_suffix('.tmp')
    temporary.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    temporary.replace(path)
    print('Wrote',path,path.stat().st_size,'bytes',dict(stats),flush=True)

if __name__=='__main__': main()
