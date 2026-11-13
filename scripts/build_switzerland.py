"""Build public-domain country context and a separate ODbL village detail mesh.
Uses the same LV95 world coordinates as build_zurich_city.py.
Dependencies: Python 3.13, shapely, pyproj, numpy, mapbox-earcut.
"""
import collections, hashlib, heapq, importlib.util, json, math, pathlib, sys, tempfile
import urllib.parse, urllib.request
from shapely.geometry import shape, Polygon, LineString, box
from shapely.ops import transform
from shapely import make_valid
from pyproj import Transformer

ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('z',ROOT/'scripts/build_zurich_city.py')
z=importlib.util.module_from_spec(spec);spec.loader.exec_module(z)
CACHE=pathlib.Path(tempfile.gettempdir())/'takt-swiss-data';CACHE.mkdir(exist_ok=True)
project=Transformer.from_crs(4326,2056,always_xy=True)
REGIONS={'andermatt':('Andermatt',8.5945,46.6369),'altdorf':('Altdorf',8.6444,46.8804),'schwyz':('Schwyz',8.652,47.0207),'luzern':('Luzern',8.3093,47.0502),'zurich':('Zürich',8.5417,47.3769),'bern':('Bern',7.4474,46.948),'basel':('Basel',7.5886,47.5596),'geneva':('Genf',6.1432,46.2044)}

def point(lon,lat):
    e,n=project.transform(lon,lat);return [round((e-z.CX)/100,3),round((z.CY-n)/100,3)]
def world(g): return z.local(transform(project.transform,g))
def load(name,url):
    p=CACHE/name
    if not p.exists(): p.write_bytes(urllib.request.urlopen(url,timeout=240).read())
    return json.loads(p.read_bytes())
def finish(name,city,bounds,attribution,counts):
    tiles=[]
    for t in z.tiles.values():
        t['meshes']=list(t['meshes'].values())
        for m in t['meshes']:
            positions=z.np.asarray(m['positions']).reshape(-1,3)
            indices=z.np.asarray(m['indices']).reshape(-1,3)
            assert z.np.isfinite(positions).all()
            assert indices.min()>=0 and indices.max()<len(positions)
            normals=z.np.cross(positions[indices[:,1]]-positions[indices[:,0]],positions[indices[:,2]]-positions[indices[:,0]])
            keep=z.np.linalg.norm(normals,axis=1)>1e-12
            removed=int((~keep).sum())
            z.stats['collapsedTrianglesRemoved']+=removed
            z.stats['triangles']-=removed
            m['indices']=indices[keep].reshape(-1).tolist()
            if not m['kind'].startswith('building'):
                assert (normals[keep,1]>=0).all(), 'Down-facing surface'
        t['meshes']=[m for m in t['meshes'] if m['indices']]
        if not t['meshes']: continue
        ps=[m['positions'] for m in t['meshes']]
        t['bounds']=[min(min(p[0::3]) for p in ps),min(min(p[2::3]) for p in ps),max(max(p[0::3]) for p in ps),max(max(p[2::3]) for p in ps)]
        tiles.append(t)
    d=dict(version=1,cityID=city,center=[8.5417,47.3769],metersPerUnit=100,bounds=list(bounds),attribution=attribution,heightNote='Höhen und Bergrelief gestalterisch angenähert; keine Höhenvermessung.',sourceDate='2026-11-13',sourceCounts=counts,statistics=dict(z.stats),boundary=[],labels=[],tiles=tiles)
    out=ROOT/'native/Takt/Resources'/name
    out.write_text(json.dumps(d,ensure_ascii=False,separators=(',',':')),encoding='utf-8')
    print(name,len(tiles),'tiles',out.stat().st_size,'bytes',dict(z.stats),flush=True)
    z.tiles.clear();z.stats.clear()

def country():
    base='https://raw.githubusercontent.com/nvkelso/natural-earth-vector/master/geojson/'
    countries=load('ne_10m_admin_0_countries.geojson',base+'ne_10m_admin_0_countries.geojson')
    swiss=world(shape(next(f for f in countries['features'] if f['properties'].get('ADM0_A3')=='CHE')['geometry'])).simplify(2,preserve_topology=True)
    z.TILE=200
    for p in z.polygons(swiss): z.surface(p,'park',-.04)
    lakes=load('ne_10m_lakes.geojson',base+'ne_10m_lakes.geojson')
    count=0
    for f in lakes['features']:
        ll=shape(f['geometry'])
        if not ll.intersects(box(5.9,45.7,10.6,47.9)):continue
        g=world(make_valid(ll)).intersection(swiss).simplify(.5,preserve_topology=True)
        for p in z.polygons(g):
            if p.area>.001:z.surface(p,'water',-.01);count+=1
    finish('switzerland-map.json','switzerland',swiss.bounds,'Made with Natural Earth — public domain',{'countryPolygons':1,'lakes':count})
    return swiss

def village():
    # The shipped source is the exact snapshot used by this release. It was
    # converted from an OSM API 0.6 map XML extract; prefer it for reproduction.
    bundled=ROOT/'native/Takt/Resources/andermatt-osm-source.json'
    if not (CACHE/'andermatt-osm.json').exists() and bundled.exists():
        (CACHE/'andermatt-osm.json').write_bytes(bundled.read_bytes())
    query='[out:json][timeout:120];(way[building](46.615,8.565,46.655,8.615);way[highway](46.615,8.565,46.655,8.615);way[waterway](46.615,8.565,46.655,8.615);way[natural=water](46.615,8.565,46.655,8.615);way[landuse](46.615,8.565,46.655,8.615););out geom;'
    osm=load('andermatt-osm.json','https://overpass.kumi.systems/api/interpreter?'+urllib.parse.urlencode({'data':query}))
    assert 'remark' not in osm,osm.get('remark')
    z.TILE=12
    extent=world(box(8.565,46.615,8.615,46.655))
    graph=collections.defaultdict(dict); locations={}; counts=collections.Counter()
    for way in osm['elements']:
        tags=way.get('tags',{}); coords=[(p['lon'],p['lat']) for p in way.get('geometry',[])]
        if len(coords)<2:continue
        line=world(LineString(coords));ident=way['id']
        if 'building' in tags and coords[0]==coords[-1] and len(coords)>3:
            geom=world(make_valid(Polygon(coords))).intersection(extent).simplify(.004,preserve_topology=True)
            try: height=float(tags.get('height',float(tags.get('building:levels',3))*3.1))/100
            except ValueError:height=.10
            height=max(.04,min(height,.5))
            for p in z.polygons(geom):
                if p.area<.0003:continue
                x,y=p.representative_point().coords[0];tx,ty=math.floor(x/12),math.floor(y/12)
                z.add_surface(z.mesh_for(tx,ty,'roof'),p,height)
                z.add_walls(z.mesh_for(tx,ty,['building','building2','building3'][ident%3]),p,height)
                counts['buildings']+=1
        elif 'highway' in tags:
            highway=tags['highway'];width=8 if highway in ['primary','secondary','trunk'] else 5 if highway in ['tertiary','residential','unclassified'] else 2
            geom=line.buffer(width/200,cap_style='flat',join_style='mitre').intersection(extent)
            for p in z.polygons(geom):z.surface(p,'road',.019)
            counts['roads']+=1
            if highway not in ['footway','path','steps','cycleway','track','pedestrian']:
                nodes=way.get('nodes',[])
                for node,coord in zip(nodes,coords):locations[node]=point(*coord)
                for a,b in zip(nodes,nodes[1:]):
                    if a in locations and b in locations:
                        dist=math.dist(locations[a],locations[b]);graph[a][b]=dist;graph[b][a]=dist
        elif 'waterway' in tags or tags.get('natural')=='water':
            geom=world(make_valid(Polygon(coords))) if coords[0]==coords[-1] and len(coords)>3 else line.buffer(.045 if tags.get('waterway')=='river' else .018)
            for p in z.polygons(geom.intersection(extent)):z.surface(p,'water',.008)
            counts['waterways']+=1
        elif 'landuse' in tags and coords[0]==coords[-1] and len(coords)>3:
            if tags['landuse'] not in ['forest','meadow','grass','farmland','recreation_ground','village_green']:continue
            geom=world(make_valid(Polygon(coords))).intersection(extent).simplify(.015,preserve_topology=True)
            for p in z.polygons(geom):z.surface(p,'forest' if tags['landuse']=='forest' else 'park',.01)
            counts['landcover']+=1
    assert counts['buildings']>100 and counts['roads']>30
    finish('andermatt-city.json','andermatt',extent.bounds,'© OpenStreetMap contributors — ODbL 1.0; openstreetmap.org/copyright',dict(counts))
    # Preserve the downloadable derivative's corresponding source extract.
    dest=ROOT/'native/Takt/Resources/andermatt-osm-source.json'
    dest.write_bytes((CACHE/'andermatt-osm.json').read_bytes())
    def route(stops):
        nearest=lambda p:min(locations,key=lambda n:math.dist(locations[n],point(*p)))
        result=[]
        for sa,sb in zip(stops,stops[1:]):
            a,b=nearest(sa),nearest(sb);dist={a:0};prev={};queue=[(0,a)]
            while queue:
                cost,n=heapq.heappop(queue)
                if n==b:break
                if cost>dist[n]:continue
                for m,w in graph[n].items():
                    if cost+w<dist.get(m,float('inf')):dist[m]=cost+w;prev[m]=n;heapq.heappush(queue,(cost+w,m))
            assert b in dist,'OSM road graph is disconnected'
            seq=[b]
            while seq[-1]!=a:seq.append(prev[seq[-1]])
            result.extend(locations[n] for n in reversed(seq))
        return list(LineString(result).simplify(.015).coords)
    return {'b31':route([(8.5937,46.6367),(8.5944,46.6323),(8.5694,46.6200)]),'b33':route([(8.5908,46.6411),(8.5937,46.6367),(8.5997,46.6325)])}

def swift(swiss,local_routes):
    centers={k:point(lon,lat) for k,(_,lon,lat) in REGIONS.items()}
    def arr(pts):return '['+','.join(f'.init({p[0]:.3f},{p[1]:.3f})' for p in pts)+']'
    outline=[list(p.exterior.coords) for p in z.polygons(swiss.simplify(4))]
    routes={};stops={}
    # Geographic waypoints: game connections, not published service alignments.
    regional={
      'altdorf':[(8.627,46.873),(8.6444,46.8804),(8.647,46.891),(8.640,46.904)],
      'schwyz':[(8.643,46.999),(8.652,47.0207),(8.659,47.028),(8.669,47.034)],
      'luzern':[(8.300,47.041),(8.3093,47.0502),(8.312,47.056),(8.324,47.062)],
      'bern':[(7.423,46.941),(7.439,46.948),(7.4474,46.948),(7.465,46.951)],
      'basel':[(7.588,47.547),(7.5886,47.5596),(7.598,47.563),(7.608,47.568)],
      'geneva':[(6.118,46.202),(6.136,46.209),(6.1432,46.2044),(6.155,46.201)]}
    for city,coords in regional.items():
        routes[city]={'b31':[point(*p) for p in coords], 'b33':[point(*p) for p in [coords[1],(coords[1][0]+.012,coords[1][1]+.008),coords[3]]]}
        stops[city]={'b31':['Westquartier',REGIONS[city][0]+' Bahnhof','Zentrum','Ostquartier'],'b33':['Bahnhof','Wohnquartier','Stadtrand']}
        for rid in ['t4','t8']:
            routes[city][rid]=routes[city]['b31' if rid=='t4' else 'b33'];stops[city][rid]=stops[city]['b31' if rid=='t4' else 'b33']
    routes['andermatt']=local_routes
    stops['andermatt']={'b31':['Andermatt Bahnhof','Andermatt Dorf','Hospental'],'b33':['Andermatt Reuss','Bahnhof','Oberalpstrasse']}
    # All main-line paths are schematic through real geographic waypoints.
    corridor=['andermatt','altdorf','schwyz','luzern','zurich','bern','basel','geneva']
    for city in REGIONS:
        routes.setdefault(city,{});stops.setdefault(city,{})
        if city!='zurich':
            target={'andermatt':'altdorf','altdorf':'schwyz','schwyz':'luzern','luzern':'zurich','bern':'basel','basel':'zurich','geneva':'bern'}[city]
            routes[city]['s12']=[centers[city],centers[target]];stops[city]['s12']=[REGIONS[city][0],REGIONS[target][0]]
        routes[city]['ic1']=[centers[city],centers['zurich' if city!='zurich' else 'bern'],centers['geneva' if city!='geneva' else 'basel']]
        stops[city]['ic1']=[REGIONS[city][0],'Zürich' if city!='zurich' else 'Bern','Genf' if city!='geneva' else 'Basel']
        routes[city]['a1']=[centers[city],centers['geneva' if city!='geneva' else 'basel']]
        stops[city]['a1']=[REGIONS[city][0],'Genf' if city!='geneva' else 'Basel']
    lines=['// Generated by scripts/build_switzerland.py. Natural Earth outline: public domain.', '// Coordinates: LV95, one world unit=100m. Non-Zurich services are fictional game routes.', 'import Foundation','', 'public struct SwissPeak: Sendable { public let name: String; public let point: MapPoint; public let height: Double }','public enum SwissGeography {', '    public static let bounds: [Double] = '+str([round(v,3) for v in swiss.bounds]), '    public static let outline: [[MapPoint]] = ['+','.join(arr(p) for p in outline)+']', '    public static let centers: [String: MapPoint] = ['+','.join(f'"{k}": .init({v[0]},{v[1]})' for k,v in centers.items())+']', '    public static func center(for cityID: String) -> MapPoint { centers[cityID] ?? centers["andermatt"]! }']
    lines+=['    public static let paths: [String: [String: [MapPoint]]] = [']
    for c,rs in routes.items():lines.append('        "'+c+'": ['+','.join('"'+r+'": '+arr(p) for r,p in rs.items())+'],')
    lines+=['    ]','    public static func points(routeID: String, cityID: String) -> [MapPoint]? { paths[cityID]?[routeID] }','    public static let stops: [String: [String: [String]]] = [']
    for c,rs in stops.items():lines.append('        "'+c+'": ['+','.join('"'+r+'": '+json.dumps(p,ensure_ascii=False) for r,p in rs.items())+'],')
    lines+=['    ]','    public static func stopNames(routeID: String, cityID: String) -> [String]? { stops[cityID]?[routeID] }','    /// Approximate geographic peak markers; rendered relief is illustrative, not surveyed.','    public static let peaks: [SwissPeak] = [']
    for name,lon,lat,h in [('Gemsstock',8.611,46.602,2961),('Dammastock',8.421,46.644,3630),('Titlis',8.437,46.772,3238),('Pilatus',8.256,46.979,2128),('Rigi',8.485,47.056,1798),('Eiger',8.005,46.578,3967),('Jungfrau',7.962,46.537,4158),('Matterhorn',7.6586,45.9763,4478),('Piz Bernina',9.908,46.383,4049),('Säntis',9.343,47.249,2502)]:
        x,y=point(lon,lat);lines.append(f'        .init(name: "{name}", point: .init({x},{y}), height: {h/100}),')
    lines+=['    ]','}']
    (ROOT/'native/Sources/TaktCore/SwissGeography.swift').write_text('\n'.join(lines)+'\n',encoding='utf-8')

if __name__=='__main__':
    swiss=country();local_routes=village();swift(swiss,local_routes)
