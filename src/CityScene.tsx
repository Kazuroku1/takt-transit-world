import { useEffect, useRef, useState } from 'react';
import * as THREE from 'three';
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import type { GameState, Mode, Point, Route } from './game';
import { ROUTES, cityFor, routeInCity } from './game';

export type SceneHandle = { zoom: (amount: number) => void; reset: () => void; focus: (id: string) => void };
type Props = { state: GameState; speed: number; selected: string | null; onSelect: (id:string)=>void; sceneRef: React.RefObject<SceneHandle | null> };
type Vehicle = { group: THREE.Group; route: Route; offset: number; tier: number };

export default function CityScene({ state, speed, selected, onSelect, sceneRef }: Props) {
  const host = useRef<HTMLDivElement>(null);
  const latest = useRef({ state, speed, selected, onSelect });
  latest.current={state,speed,selected,onSelect};
  const [failed,setFailed]=useState(false);

  useEffect(()=>{
    if(!host.current) return;
    const el=host.current;
    let renderer:THREE.WebGLRenderer;
    try { renderer=new THREE.WebGLRenderer({antialias:true,alpha:true,powerPreference:'high-performance'}); }
    catch {setFailed(true);return;}
    renderer.setPixelRatio(Math.min(window.devicePixelRatio,1.8));
    renderer.shadowMap.enabled=true;
    renderer.shadowMap.type=THREE.PCFSoftShadowMap;
    renderer.outputColorSpace=THREE.SRGBColorSpace;
    renderer.toneMapping=THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure=1.05;
    el.appendChild(renderer.domElement);
    renderer.domElement.setAttribute('aria-label','Interaktive 3D-Stadt. Ziehen zum Drehen, mit zwei Fingern zoomen. Fahrzeuge antippen, um ihre Linie zu öffnen.');
    renderer.domElement.setAttribute('role','img');
    const scene=new THREE.Scene();
    const camera=new THREE.OrthographicCamera(-24,24,19,-19,0.1,180);
    camera.position.set(33,31,38); camera.lookAt(0,0,0);
    const controls=new OrbitControls(camera,renderer.domElement);
    controls.enableDamping=true; controls.dampingFactor=.075;
    controls.enablePan=true; controls.minZoom=.65; controls.maxZoom=2.8;
    controls.minPolarAngle=.3; controls.maxPolarAngle=Math.PI/2.65;
    controls.target.set(0,.1,0); controls.rotateSpeed=.5;
    controls.touches.ONE=THREE.TOUCH.ROTATE; controls.touches.TWO=THREE.TOUCH.DOLLY_PAN;
    const hemi=new THREE.HemisphereLight('#fff8e7','#8caa88',2);scene.add(hemi);
    const sun=new THREE.DirectionalLight('#fff1d8',2.4);sun.position.set(-16,30,15);sun.castShadow=true;
    sun.shadow.mapSize.set(2048,2048);sun.shadow.camera.left=-28;sun.shadow.camera.right=28;sun.shadow.camera.top=28;sun.shadow.camera.bottom=-28;sun.shadow.normalBias=.035;sun.shadow.bias=-.0003;sun.shadow.radius=4;scene.add(sun);
    const materialCache=new Map<string,THREE.MeshStandardMaterial>();
    const mat=(color:string)=>{
      if(!materialCache.has(color))materialCache.set(color,new THREE.MeshStandardMaterial({color,roughness:.9,metalness:0}));
      return materialCache.get(color)!;
    };
    const box=(w:number,h:number,d:number,color:string,x:number,y:number,z:number,parent:THREE.Object3D=scene)=>{
      const mesh=new THREE.Mesh(new THREE.BoxGeometry(w,h,d),mat(color));mesh.position.set(x,y,z);mesh.castShadow=h>.15;mesh.receiveShadow=true;parent.add(mesh);return mesh;
    };
    const cylinder=(r1:number,r2:number,h:number,color:string,x:number,y:number,z:number,parent:THREE.Object3D=scene,sides=8)=>{
      const m=new THREE.Mesh(new THREE.CylinderGeometry(r1,r2,h,sides),mat(color));m.position.set(x,y,z);m.castShadow=true;m.receiveShadow=true;parent.add(m);return m;
    };
    const sphere=(r:number,color:string,x:number,y:number,z:number,parent:THREE.Object3D=scene)=>{
      const m=new THREE.Mesh(new THREE.IcosahedronGeometry(r,1),mat(color));m.position.set(x,y,z);m.castShadow=true;parent.add(m);return m;
    };
    const tree=(x:number,z:number,scale=1)=>{
      const g=new THREE.Group();g.position.set(x,0,z);g.scale.setScalar(scale);scene.add(g);
      cylinder(.07,.1,.8,'#8e7754',0,.5,0,g);
      sphere(.55,'#78a36c',0,1.2,0,g);sphere(.4,'#94b67b',.1,1.6,.05,g);
      return g;
    };
    let seed=state.cityId.split('').reduce((v,c)=>v+c.charCodeAt(0),0);
    const rand=()=>{seed=(seed*16807)%2147483647;return(seed-1)/2147483646;};
    const city=cityFor(state.cityId);
    // A handmade miniature: every street and service shares the same coordinates.
    box(32,.8,28,'#ccbca0',0,-.5,0);
    box(32,.22,28,'#aac28d',0,-.05,0);
    box(31.7,.06,27.7,'#b6cb9a',0,.09,0);
    const water=box(3.8,.13,28.02,'#81c8d1',7.8,.13,0);
    water.material=new THREE.MeshStandardMaterial({color:'#83cbd1',roughness:.25,metalness:.12});
    box(.25,.18,28,'#e4dcc2',5.77,.17,0);box(.25,.18,28,'#e4dcc2',9.83,.17,0);
    const road='#a6aaa0', pavement='#d7d4c2';
    for(const x of [-10,-4,2,12]) {
      box(1.95,.08,26,pavement,x,.16,0);box(1.32,.05,26,road,x,.22,0);
      for(let z=-12.5;z<13;z+=1.5)box(.035,.011,.65,'#dedccd',x,.25,z);
    }
    for(const z of [-9,-3,3,9]) {
      box(30,.08,1.95,pavement,0,.17,z);box(30,.06,1.32,road,0,.23,z);
      for(let x=-14.5;x<15;x+=1.5)box(.65,.011,.035,'#dedccd',x,.265,z);
      // Bridge parapets and supports above the river.
      box(4.2,.28,1.8,'#c4bdaa',7.8,.17,z);
      box(4.3,.06,1.32,road,7.8,.35,z);
      for(const dz of [-.82,.82]){
        box(4.4,.055,.045,'#c5c4b6',7.8,.79,z+dz);
        for(let x=5.8;x<10;x+=.5)box(.035,.44,.035,'#c5c4b6',x,.56,z+dz);
      }
    }
    for(const x of [-10,-4,2,12])for(const z of [-9,-3,3,9]){
      box(1.32,.014,1.32,road,x,.272,z);
      for(let i=0;i<5;i++){
        box(.13,.012,.5,'#e8e5cf',x-.48+i*.24,.28,z+1.03);
        box(.5,.012,.13,'#e8e5cf',x+1.03,.28,z-.48+i*.24);
      }
    }
    // Quiet railway corridor, with real ties and twin rails.
    box(30,.07,1.45,'#b5b2a2',0,.2,-11.8);
    for(let x=-15;x<15;x+=.45)box(.1,.06,1.16,'#9e927c',x,.27,-11.8);
    for(const z of [-12.13,-11.47])box(30,.055,.055,'#737c7a',0,.32,z);

    const buildings: {x:number;z:number;w:number;d:number;h:number;color:string;roof?:boolean}[]=[];
    const palette=['#e9d7b9','#f1e8cc','#d9bfa5','#d8d7c4','#e9c2a8','#c3cfc5','#e4d6c7'];
    for(const cx of [-13,-7,-1,14])for(const cz of [-6,0,6,11.5]) {
      if((cx===-7 && cz===0)||(cx===-1&&cz===6)||(cx===14&&cz===11.5))continue;
      for(let i=0;i<3;i++){
        const x=cx+(i===0?-1.05:i===1?1.05:-.9);
        const z=cz+(i===2?1.05:-.7);
        const h=1.1+rand()*2.5;
        buildings.push({x,z,w:1.45+rand()*.4,d:1.45,h,color:palette[Math.floor(rand()*palette.length)],roof:rand()>.22});
      }
    }
    // Little lake-side residential row.
    for(const z of [-6,0,6,11])buildings.push({x:4.3,z,w:1.5,d:1.65,h:1.25+rand()*1.25,color:palette[Math.floor(rand()*palette.length)],roof:true});
    buildings.forEach(({x,z,w,d,h,color,roof},i)=>{
      box(w+.22,.12,d+.22,'#d7cfb8',x,.22,z);
      box(w,h,d,color,x,.28+h/2,z);
      // Shop fronts, doors, awnings and many inset blue windows.
      const windowColor=state.settings.night?'#ffe3a0':'#789da6';
      for(let y=.78;y<h+.05;y+=.6)for(const dx of [-w*.26,w*.26]){
        box(.25,.3,.025,windowColor,x+dx,y,z+d/2+.015);
        box(.025,.3,.25,windowColor,x+w/2+.015,y,z+dx);
        box(.025,.3,.25,windowColor,x-w/2-.015,y,z+dx);
      }
      box(.32,.55,.04,'#7b8f85',x,.55,z+d/2+.025);
      if(i%3===0){
        box(w*.8,.07,.5,i%2?'#b7c6a0':'#d99c7b',x,.92,z+d/2+.17);
        box(w*.8,.16,.05,i%2?'#a0b085':'#cd8e6b',x,.84,z+d/2+.39);
      }
      if(roof){
        const g=new THREE.BufferGeometry();
        const y=h+.28,peak=y+.65;
        const vertices=new Float32Array([
          x-w/2-.1,y,z-d/2-.1, x+w/2+.1,y,z-d/2-.1, x,peak,z-d/2-.1,
          x-w/2-.1,y,z+d/2+.1, x,peak,z+d/2+.1, x+w/2+.1,y,z+d/2+.1,
          x-w/2-.1,y,z-d/2-.1, x,peak,z-d/2-.1, x,peak,z+d/2+.1,
          x-w/2-.1,y,z-d/2-.1, x,peak,z+d/2+.1, x-w/2-.1,y,z+d/2+.1,
          x+w/2+.1,y,z+d/2+.1, x,peak,z+d/2+.1, x,peak,z-d/2-.1,
          x+w/2+.1,y,z+d/2+.1, x,peak,z-d/2-.1, x+w/2+.1,y,z-d/2-.1]);
        g.setAttribute('position',new THREE.BufferAttribute(vertices,3));g.computeVertexNormals();
        const m=new THREE.Mesh(g,mat(i%4===0?'#88978d':i%3===0?'#b78d70':'#c58b72'));m.castShadow=true;m.receiveShadow=true;scene.add(m);
        if(i%3===0)box(.22,.5,.23,'#e0c9ad',x+.35,peak-.12,z-.25);
      }else{
        box(w+.15,.14,d+.15,'#b7b8a8',x,h+.32,z);
        box(.42,.24,.45,'#b3b9ad',x+.25,h+.5,z-.3);
      }
    });
    // The old-town church, with a clock tower and copper spire.
    box(1.4,2.4,2.6,'#eee4c8',-7.1,1.42,-6.1);
    box(.95,4.5,.95,'#e9dbbc',-7.1,2.45,-4.65);
    cylinder(0,.8,2,'#7b9d8f',-7.1,5.6,-4.65,scene,4).rotation.y=Math.PI/4;
    for(const axis of ['x','z']){
      const clock=new THREE.Mesh(new THREE.CircleGeometry(.27,24),mat('#faf3da'));
      if(axis==='x'){clock.position.set(-6.615,3.95,-4.65);clock.rotation.y=Math.PI/2;}else clock.position.set(-7.1,3.95,-4.16);
      scene.add(clock);
      if(axis==='z'){box(.025,.23,.02,'#6d7b73',-7.1,4.03,-4.14);box(.17,.025,.02,'#6d7b73',-7.02,3.95,-4.14);}
    }
    // Central park and fountain.
    box(4.3,.1,3.8,'#a5be80',-7,.2,0);
    box(4,.035,.6,'#ddcfb2',-7,.27,.2);box(.6,.035,3.6,'#ddcfb2',-7,.28,0);
    cylinder(.75,.82,.18,'#dad6c1',-7,.37,0,scene,24);
    cylinder(.63,.63,.06,'#86cbd0',-7,.49,0,scene,24);
    cylinder(.1,.14,.65,'#d2d1bd',-7,.74,0);
    cylinder(.38,.3,.08,'#d2d1bd',-7,1.08,0,scene,16);
    for(const [x,z]of [[-8.5,-1.2],[-5.4,-1.2],[-8.5,1.3],[-5.4,1.3]])tree(x,z,.85);
    const bench=(x:number,z:number)=>{box(.7,.09,.26,'#a78d64',x,.5,z);for(const dx of [-.26,.26])box(.06,.32,.24,'#7f8c78',x+dx,.32,z);box(.7,.26,.06,'#a78d64',x,.66,z-.13);};
    bench(-8.2,.9);bench(-5.7,-.8);
    // Station platform, glass canopy, and little clock sign.
    box(5.2,.3,1.2,'#dcd5bf',-1,.4,-10.5);
    box(4.6,.1,1.25,'#a4bcc0',-1,1.55,-10.5);
    for(const x of [-2.8,-1,.8])box(.08,1.1,.08,'#ece5cf',x,.96,-10.5);
    box(1.3,1.5,1.1,'#edd7b9',-4.3,.9,-11.2);
    // A cafe terrace at the water and a bright small sports court.
    box(3.2,.08,3.8,'#91aaa0',-.6,.23,6.3);
    const court=new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(2.5,.01,3)),new THREE.LineBasicMaterial({color:'#e6ebd5'}));court.position.set(-.6,.29,6.3);scene.add(court);
    box(2.5,.012,.035,'#e6ebd5',-.6,.31,6.3);
    const ring=new THREE.Mesh(new THREE.RingGeometry(.48,.51,24),mat('#e6ebd5'));ring.rotation.x=-Math.PI/2;ring.position.set(-.6,.32,6.3);scene.add(ring);
    for(const z of [-6,0,6,11]){
      box(.5,.18,1.2,'#c1a884',6.25,.35,z);
      for(const dz of [-.4,.4])box(.12,.6,.12,'#9e8a67',6.5,.4,z+dz);
    }
    // Promenade, street furniture and carefully placed greenery.
    for(let z=-12;z<13;z+=2.1){tree(10.45,z,.72);if(Math.abs(z+3)>1&&Math.abs(z-3)>1&&Math.abs(z-9)>1&&Math.abs(z+9)>1)tree(5.05,z,.65);}
    for(let i=0;i<36;i++){
      const x=-15+rand()*19;const z=-12+rand()*25;
      const nearRoad=[-10,-4,2].some(rx=>Math.abs(x-rx)<1.5)||[-9,-3,3,9].some(rz=>Math.abs(z-rz)<1.5);
      const nearBuilding=buildings.some(b=>Math.abs(x-b.x)<1.3&&Math.abs(z-b.z)<1.4);
      if(!nearRoad&&!nearBuilding)tree(x,z,.65+rand()*.4);
    }
    const stopPoints:Point[]=[[-10,9],[-10,-3],[-4,-9],[2,-9],[-4,9],[2,3],[12,3],[12,9]];
    stopPoints.forEach(([x,z],i)=>{
      box(.7,.07,.65,'#e6d6ad',x-.95,.29,z);
      box(.045,.9,.045,'#7c8d7c',x-.95,.75,z);
      box(.24,.25,.05,'#e4ba54',x-.95,1.19,z);
      if(i%2===0){box(.55,.75,.05,'#a5beb8',x-1.15,.68,z-.25);box(.7,.06,.5,'#a1b3a0',x-1.1,1.1,z-.04);}
    });
    for(const [x,z]of [[-9,-7],[-3,1],[1,-7],[13,7],[-9,5],[1,5]]){
      cylinder(.025,.04,1.4,'#7a8b7c',x,.92,z);sphere(.09,'#fff2c5',x,1.67,z);
    }
    // Distant hills, tiny mountain huts, and the cableway terminals.
    for(const [x,z,r,h]of [[-13,-14,3,4],[-16,-13,2.5,3],[-12,-16,2.8,5]]){
      cylinder(0,r,h,'#93aa86',x,h/2-.1,z,scene,6);
      if(h>4)cylinder(0,.65,1.15,'#e8e8d6',x,h-.55,z,scene,6);
    }
    box(.8,.6,.8,'#dfc8a3',-14.7,3.1,-14.7);

    const makeLabel=(text:string,x:number,y:number,z:number)=>{
      const canvas=document.createElement('canvas');canvas.width=512;canvas.height=96;
      const ctx=canvas.getContext('2d')!;ctx.font='600 28px sans-serif';ctx.textAlign='center';
      const w=ctx.measureText(text).width+45;
      ctx.fillStyle='rgba(255,253,242,.93)';ctx.beginPath();ctx.roundRect((512-w)/2,8,w,62,20);ctx.fill();
      ctx.fillStyle='#536851';ctx.fillText(text,256,49);
      const tex=new THREE.CanvasTexture(canvas);tex.colorSpace=THREE.SRGBColorSpace;
      const sprite=new THREE.Sprite(new THREE.SpriteMaterial({map:tex,depthTest:false,transparent:true,opacity:.85}));
      sprite.scale.set(6,1.12,1);sprite.position.set(x,y,z);sprite.renderOrder=9;scene.add(sprite);return sprite;
    };
    makeLabel(state.cityId==='zurich'?'ALTSTADT':city.name.toUpperCase(),-7,4.2,-.2);
    makeLabel(state.cityId==='zurich'?'HAUPTBAHNHOF':routeInCity(ROUTES[0],state.cityId).to,-1,2.4,-10.8);
    makeLabel(state.cityId==='zurich'?'ZÜRICHSEE':'AM WASSER',8,.7,12.5);

    // Batch static architecture by material. This keeps the miniature affordable on iPhone GPUs.
    scene.updateMatrixWorld(true);
    const batches=new Map<string,{material:THREE.Material;castShadow:boolean;geometries:THREE.BufferGeometry[];meshes:THREE.Mesh[]}>();
    scene.traverse(obj=>{
      if(!(obj instanceof THREE.Mesh)||Array.isArray(obj.material))return;
      const key=obj.material.uuid+String(obj.castShadow);
      if(!batches.has(key))batches.set(key,{material:obj.material,castShadow:obj.castShadow,geometries:[],meshes:[]});
      let geometry=obj.geometry.clone().applyMatrix4(obj.matrixWorld);
      if(geometry.index){const expanded=geometry.toNonIndexed();geometry.dispose();geometry=expanded;}
      for(const attribute of Object.keys(geometry.attributes))if(!['position','normal'].includes(attribute))geometry.deleteAttribute(attribute);
      if(!geometry.getAttribute('normal'))geometry.computeVertexNormals();
      batches.get(key)!.geometries.push(geometry);batches.get(key)!.meshes.push(obj);
    });
    for(const batch of batches.values()){
      const geometry=mergeGeometries(batch.geometries,false);
      if(geometry){const mesh=new THREE.Mesh(geometry,batch.material);mesh.castShadow=batch.castShadow;mesh.receiveShadow=true;scene.add(mesh);for(const original of batch.meshes){original.removeFromParent();original.geometry.dispose();}}
      batch.geometries.forEach(g=>g.dispose());
    }

    const vehicles:Vehicle[]=[];
    const transport=new THREE.Group();scene.add(transport);
    let routeSignature='';
    const selectable:THREE.Object3D[]=[];
    const drawPath=(points:Point[],color:string,y:number,dashed=false)=>{
      const points3=points.map(([x,z])=>new THREE.Vector3(x,y,z));
      const geo=new THREE.BufferGeometry().setFromPoints(points3);
      const line=dashed?new THREE.Line(geo,new THREE.LineDashedMaterial({color,dashSize:.28,gapSize:.22,transparent:true,opacity:.75})):new THREE.Line(geo,new THREE.LineBasicMaterial({color,transparent:true,opacity:.7}));
      line.computeLineDistances();transport.add(line);return line;
    };
    const makeVehicle=(mode:Mode,color:string)=>{
      const g=new THREE.Group();
      if(mode==='ship'){
        const hull=box(.62,.24,1.6,'#f1eee0',0,.28,0,g);hull.rotation.z=.02;
        box(.49,.32,.85,'#f4f1df',0,.55,-.05,g);box(.52,.13,.78,color,0,.75,-.05,g);
        box(.5,.14,.55,'#729ba6',0,.58,-.1,g);box(.15,.33,.15,'#d1b992',0,.89,.3,g);
      }else if(mode==='plane'){
        const body=sphere(.3,'#f9f5e9',0,.2,0,g);body.scale.set(.8,.7,3.7);
        box(2.7,.06,.4,'#e9e9dc',0,.25,.1,g);box(1.0,.06,.3,color,0,.3,.9,g);box(.06,.5,.4,color,0,.48,.8,g);
      }else if(mode==='cable'){
        box(.65,.6,.65,color,0,.55,0,g);box(.68,.3,.68,'#91b4b8',0,.8,0,g);box(.05,.5,.05,'#75857c',0,1.2,0,g);
      }else{
        const len=mode==='bus'?1.13:mode==='tram'?2.0:2.5;
        const segments=mode==='train'||mode==='metro'?2:1;
        for(let i=0;i<segments;i++){
          const z=i*(len+.12);
          box(.5,.46,len,color,0,.52,z,g);
          box(.48,.16,len*.92,'#88a9ae',0,.6,z,g);
          box(.5,.07,len*.96,'#f2ead7',0,.8,z,g);
          box(.39,.19,.02,'#67929d',0,.59,z-len/2-.015,g);
          for(const dz of [-len*.31,len*.31])for(const dx of [-.26,.26]){
            const tire=cylinder(.09,.09,.04,'#535d56',dx,.27,z+dz,g,12);tire.rotation.z=Math.PI/2;
          }
          box(.12,.05,.02,'#fff7b0',-.15,.42,z-len/2-.025,g);box(.12,.05,.02,'#fff7b0',.15,.42,z-len/2-.025,g);
        }
      }
      return g;
    };
    const disposeObject=(root:THREE.Object3D)=>root.traverse(obj=>{
      if(obj instanceof THREE.Mesh||obj instanceof THREE.Line){obj.geometry.dispose();if(obj.material instanceof THREE.LineBasicMaterial)obj.material.dispose();}
    });
    const syncRoutes=()=>{
      const own=latest.current.state.cities[state.cityId].routes;
      const sig=own.map(o=>o.id+o.tier).join('|')+'|'+latest.current.selected;
      if(sig===routeSignature)return;routeSignature=sig;
      transport.children.forEach(disposeObject);transport.clear();vehicles.length=0;selectable.length=0;
      for(const o of own){
        const route=ROUTES.find(r=>r.id===o.id)!;
        const y=route.mode==='ship'?.05:route.mode==='plane'?5:route.mode==='cable'?3.4:route.mode==='train'?.16:.1;
        const path=route.points.map(([x,z]):Point=>route.mode==='train'?[x,-11.8]:[x,z]);
        const r={...route,points:path};
        const pathY=route.mode==='ship'?.23:route.mode==='plane'?5:route.mode==='cable'?4.65:.4;
        drawPath(path,route.color,pathY,route.mode==='metro');
        if(latest.current.selected===r.id){
          drawPath(path,'#ffffff',pathY+.015);
          for(const [x,z]of path){const marker=new THREE.Mesh(new THREE.RingGeometry(.18,.28,20),mat(route.color));marker.rotation.x=-Math.PI/2;marker.position.set(x,pathY+.025,z);transport.add(marker);}
        }
        if(route.mode==='cable'){
          const cablePoints=path.map(([x,z])=>new THREE.Vector3(x,4.85,z));
          const wire=new THREE.Line(new THREE.BufferGeometry().setFromPoints(cablePoints),new THREE.LineBasicMaterial({color:'#65776c'}));transport.add(wire);
          for(const [x,z] of path)cylinder(.05,.08,4.5,'#95a193',x,2.6,z,transport);
        }
        for(let i=0;i<o.tier;i++){
          const g=makeVehicle(route.mode,route.color);g.userData.routeId=route.id;g.userData.baseY=y;transport.add(g);
          g.traverse(c=>{c.userData.routeId=route.id;if(c instanceof THREE.Mesh)selectable.push(c);});
          vehicles.push({group:g,route:r,offset:i/o.tier,tier:o.tier});
        }
      }
    };
    // Footpaths follow pavements; people wait, walk and gather near stops.
    const people:{g:THREE.Group;x:number;z:number;axis:'x'|'z';phase:number;color:string}[]=[];
    for(let i=0;i<64;i++){
      const axis=i%2?'x':'z';const fixed=axis==='x'?[-9,-3,3,9][i%4]+.88:[-10,-4,2,12][i%4]+.88;
      const variable=-12+rand()*24;
      const x=axis==='x'?variable:fixed,z=axis==='x'?fixed:variable;
      if(x>5.5&&x<10)continue;
      const g=new THREE.Group();g.position.set(x,.3,z);const color=['#d67d63','#6d98aa','#f1bd63','#758e6d','#b4a0be'][i%5];
      box(.12,.23,.13,color,0,.25,0,g);sphere(.075,'#d8b69a',0,.43,0,g);
      box(.045,.14,.06,'#6b776f',-.035,.08,0,g);box(.045,.14,.06,'#6b776f',.035,.08,0,g);
      scene.add(g);people.push({g,x,z,axis,phase:rand()*10,color});
    }
    const ripples:THREE.Mesh[]=[];
    for(let i=0;i<16;i++){
      const r=box(.15+rand()*.5,.006,.025,'#c0e5df',6.3+rand()*2.8,.216,-13+rand()*26);
      ripples.push(r);
    }
    const birds:THREE.Group[]=[];
    for(let i=0;i<4;i++){
      const g=new THREE.Group();box(.24,.025,.065,'#f9f5e8',-.1,0,0,g).rotation.z=.22;box(.24,.025,.065,'#f9f5e8',.1,0,0,g).rotation.z=-.22;scene.add(g);birds.push(g);
    }
    const selectionRing=new THREE.Mesh(new THREE.RingGeometry(.55,.62,32),new THREE.MeshBasicMaterial({color:'#fff5cf',side:THREE.DoubleSide,transparent:true,opacity:.8}));selectionRing.rotation.x=-Math.PI/2;scene.add(selectionRing);
    selectionRing.visible=false;
    const raycaster=new THREE.Raycaster();const mouse=new THREE.Vector2();
    let pointerDown={x:0,y:0};
    const down=(e:PointerEvent)=>{pointerDown={x:e.clientX,y:e.clientY};};
    const up=(e:PointerEvent)=>{
      if(Math.hypot(e.clientX-pointerDown.x,e.clientY-pointerDown.y)>6)return;
      const rect=el.getBoundingClientRect();mouse.set((e.clientX-rect.left)/rect.width*2-1,-(e.clientY-rect.top)/rect.height*2+1);
      raycaster.setFromCamera(mouse,camera);const hit=raycaster.intersectObjects(selectable)[0];
      if(hit)latest.current.onSelect(hit.object.userData.routeId);
    };
    renderer.domElement.addEventListener('pointerdown',down);renderer.domElement.addEventListener('pointerup',up);
    const home=()=>{camera.position.set(33,31,38);controls.target.set(0,.1,0);camera.zoom=1;camera.updateProjectionMatrix();controls.update();};
    sceneRef.current={zoom:(amount)=>{camera.zoom=THREE.MathUtils.clamp(camera.zoom+amount,.65,2.8);camera.updateProjectionMatrix();},reset:home,focus:(id)=>{
      const r=ROUTES.find(r=>r.id===id);if(!r)return;
      const [x,z]=r.points[Math.floor(r.points.length/2)];const delta=new THREE.Vector3(x,.3,z).sub(controls.target);camera.position.add(delta);controls.target.add(delta);camera.zoom=1.45;camera.updateProjectionMatrix();
    }};
    const resize=()=>{
      const w=el.clientWidth,h=el.clientHeight;if(!w||!h)return;
      renderer.setSize(w,h);
      const aspect=w/h;const size=aspect<1?Math.max(25,24/aspect):20.5;
      camera.left=-size*aspect;camera.right=size*aspect;camera.top=size;camera.bottom=-size;camera.updateProjectionMatrix();
    };
    const observer=new ResizeObserver(resize);observer.observe(el);resize();
    let frame=0;let time=0;let last=performance.now();let lastNight=state.settings.night;
    const updateNight=(night:boolean)=>{
      hemi.intensity=night?1.1:2;sun.intensity=night?1:2.4;sun.color.set(night?'#a5bcd7':'#fff1d8');renderer.toneMappingExposure=night?.8:1.05;
    };updateNight(lastNight);
    const animate=(now:number)=>{
      frame=requestAnimationFrame(animate);
      const dt=Math.min((now-last)/1000,.05);last=now;
      const {state:s,speed:playSpeed}=latest.current;
      if(document.hidden)return;
      time+=dt*playSpeed;syncRoutes();
      if(lastNight!==s.settings.night){lastNight=s.settings.night;updateNight(lastNight);}
      vehicles.forEach(({group:g,route:r,offset})=>{
        const p=((time/r.duration)*.5+offset)%1;
        // Shuttles reverse only at their actual terminals.
        const t=p<.5?p*2:(1-p)*2;
        const lens:number[]=[];let length=0;
        for(let i=1;i<r.points.length;i++){length+=Math.hypot(r.points[i][0]-r.points[i-1][0],r.points[i][1]-r.points[i-1][1]);lens.push(length);}
        const distance=t*length;let index=lens.findIndex(l=>l>=distance);if(index<0)index=lens.length-1;
        const start=index===0?0:lens[index-1];const local=(distance-start)/(lens[index]-start);
        const a=r.points[index],b=r.points[index+1];
        g.position.set(THREE.MathUtils.lerp(a[0],b[0],local),g.userData.baseY,THREE.MathUtils.lerp(a[1],b[1],local));
        const direction=p<.5?1:-1;g.rotation.y=Math.atan2(-(b[0]-a[0])*direction,-(b[1]-a[1])*direction);
        if(r.mode==='ship'&&!s.settings.reducedMotion){g.rotation.z=Math.sin(time*2+offset)*.025;g.position.y+=Math.sin(time*2)*.025;}
        if(r.mode==='plane')g.position.y=4+Math.sin(t*Math.PI)*4;
        if(r.mode==='metro'){g.position.y=.15;g.visible=Math.floor(t*12)%3===0||s.cityId===state.cityId&&latest.current.selected===r.id;}
      });
      selectionRing.visible=Boolean(latest.current.selected);
      const selectedVehicle=vehicles.find(v=>v.route.id===latest.current.selected);
      if(selectedVehicle){selectionRing.position.copy(selectedVehicle.group.position);selectionRing.position.y+=.02;selectionRing.scale.setScalar(1+Math.sin(time*3)*.1);}
      if(!s.settings.reducedMotion){
        people.forEach(({g,x,z,axis,phase})=>{
          const v=Math.sin(time*.08+phase)*1.3;
          g.position[axis]=axis==='x'?x+v:z+v;
          g.position.y=.31+Math.abs(Math.sin(time*5+phase))*.015;
        });
        ripples.forEach((r,i)=>{r.position.x=6.5+(i*.39+time*.06)%2.6;r.scale.x=.8+Math.sin(time+i)*.3;});
        birds.forEach((g,i)=>{const t=time*.06+i*1.5;g.position.set(Math.cos(t)*11,6+i*.4,Math.sin(t)*9);g.rotation.y=-t;g.rotation.z=Math.sin(time*3+i)*.1;});
      }
      controls.update();renderer.render(scene,camera);
    };frame=requestAnimationFrame(animate);
    return ()=>{
      cancelAnimationFrame(frame);observer.disconnect();controls.dispose();
      renderer.domElement.removeEventListener('pointerdown',down);renderer.domElement.removeEventListener('pointerup',up);
      scene.traverse(obj=>{
        if(obj instanceof THREE.Mesh||obj instanceof THREE.Line){obj.geometry.dispose();const mats=Array.isArray(obj.material)?obj.material:[obj.material];for(const m of mats){if('map' in m && m.map instanceof THREE.Texture)m.map.dispose();m.dispose();}}
        if(obj instanceof THREE.Sprite){obj.material.map?.dispose();obj.material.dispose();}
      });
      for(const m of materialCache.values())m.dispose();
      renderer.dispose();renderer.domElement.remove();sceneRef.current=null;
    };
  },[state.cityId,sceneRef]);

  return <div className="scene-host" ref={host}>{failed&&<div className="scene-fallback"><strong>Die 3D-Stadt braucht WebGL.</strong><p>Bitte öffne Takt in einem aktuellen Browser. Dein Verkehrsnetz und alle Menüs funktionieren weiterhin.</p></div>}</div>;
}
