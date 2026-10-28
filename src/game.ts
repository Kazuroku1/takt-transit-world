export type Mode = 'bus' | 'tram' | 'train' | 'metro' | 'ship' | 'plane' | 'cable';
export type Point = [number, number];
export type Route = { id: string; number: string; name: string; from: string; to: string; mode: Mode; color: string; cost: number; level: number; duration: number; capacity: number; fare: number; points: Point[]; stops: string[] };
export type City = { id: string; name: string; country: string; flag: string; tagline: string; cost: number; level: number; x: number; y: number; accent: string; population: string };
export type OwnedRoute = { id: string; tier: number; carried: number; progress: number };
export type CityState = { routes: OwnedRoute[] };
export type Settings = { sound: boolean; reducedMotion: boolean; night: boolean };
export type GameState = { version: 1; cash: number; xp: number; passengers: number; earned: number; cityId: string; cities: Record<string, CityState>; claimed: string[]; seconds: number; savedAt: number; settings: Settings; event: { kind: 'rush' | 'festival'; endsAt: number } | null; lastEvent: number };

export const MODES: Record<Mode, { name: string; plural: string; color: string; level: number; description: string }> = {
  bus: { name: 'Bus', plural: 'Busse', color: '#e9a443', level: 1, description: 'Kleine Wege. Grosse Verbindungen.' },
  tram: { name: 'Tram', plural: 'Trams', color: '#df725c', level: 2, description: 'Der Herzschlag deiner Innenstadt.' },
  train: { name: 'Zug', plural: 'Züge', color: '#628cb0', level: 3, description: 'Mehr Menschen. Neue Horizonte.' },
  metro: { name: 'Metro', plural: 'Metros', color: '#9a81b5', level: 4, description: 'Unter der Stadt geht es vorwärts.' },
  ship: { name: 'Schiff', plural: 'Schiffe', color: '#55a69e', level: 5, description: 'Dein Netz geht übers Wasser.' },
  cable: { name: 'Seilbahn', plural: 'Seilbahnen', color: '#859e54', level: 6, description: 'Mit Aussicht nach ganz oben.' },
  plane: { name: 'Flugzeug', plural: 'Flugzeuge', color: '#d48da9', level: 7, description: 'Die Welt liegt dir zu Füssen.' },
};
export const CITIES: City[] = [
  { id: 'zurich', name: 'Zürich', country: 'Schweiz', flag: 'CH', tagline: 'Zwischen See und Stadtleben.', cost: 0, level: 1, x: 49, y: 31, accent: '#75a98a', population: '443 000' },
  { id: 'bern', name: 'Bern', country: 'Schweiz', flag: 'CH', tagline: 'Eine Altstadt voller neuer Wege.', cost: 2800, level: 3, x: 47, y: 33, accent: '#c49d71', population: '145 000' },
  { id: 'paris', name: 'Paris', country: 'Frankreich', flag: 'FR', tagline: 'Nächster Halt: la vie en rose.', cost: 6500, level: 4, x: 45, y: 29, accent: '#b09aab', population: '2,1 Mio.' },
  { id: 'london', name: 'London', country: 'Grossbritannien', flag: 'GB', tagline: 'Mind the gap. Make the connection.', cost: 12000, level: 5, x: 43, y: 24, accent: '#a4a8bc', population: '9 Mio.' },
  { id: 'newyork', name: 'New York', country: 'USA', flag: 'US', tagline: 'Ein Netz, das niemals schläft.', cost: 20000, level: 6, x: 25, y: 34, accent: '#b7a183', population: '8,3 Mio.' },
  { id: 'tokyo', name: 'Tokio', country: 'Japan', flag: 'JP', tagline: 'Millionen Menschen. Dein Takt.', cost: 35000, level: 7, x: 87, y: 39, accent: '#d4a2ae', population: '14 Mio.' },
  { id: 'rio', name: 'Rio de Janeiro', country: 'Brasilien', flag: 'BR', tagline: 'Mit Leichtigkeit durch die Küstenstadt.', cost: 45000, level: 8, x: 34, y: 71, accent: '#88af77', population: '6,7 Mio.' },
  { id: 'sydney', name: 'Sydney', country: 'Australien', flag: 'AU', tagline: 'Neue Verbindungen am anderen Ende der Welt.', cost: 60000, level: 9, x: 91, y: 78, accent: '#d0b178', population: '5,3 Mio.' },
];

export const ROUTES: Route[] = [
  { id: 'b31', number: '31', name: 'Die Quartierlinie', from: 'Altstetten', to: 'Hauptbahnhof', mode: 'bus', color: '#dfa137', cost: 0, level: 1, duration: 14, capacity: 8, fare: 4, points: [[-10,9],[-10,3],[-10,-3],[-4,-3],[-4,-9],[2,-9]], stops: ['Altstetten','Hardplatz','Langstrasse','Hauptbahnhof'] },
  { id: 'b33', number: '33', name: 'Einmal ums Quartier', from: 'Triemli', to: 'Tiefenbrunnen', mode: 'bus', color: '#7e9f63', cost: 550, level: 1, duration: 18, capacity: 12, fare: 4, points: [[-4,9],[-4,3],[-4,-3],[2,-3],[2,3],[12,3],[12,9]], stops: ['Triemli','Wiedikon','Central','Bellevue','Tiefenbrunnen'] },
  { id: 't4', number: '4', name: 'Mitten durchs Leben', from: 'Bahnhofquai', to: 'Bellevue', mode: 'tram', color: '#df725c', cost: 1100, level: 2, duration: 20, capacity: 24, fare: 5, points: [[-10,-9],[-4,-9],[2,-9],[2,-3],[2,3],[12,3],[12,9]], stops: ['Bahnhofquai','Hauptbahnhof','Central','Bellevue'] },
  { id: 't8', number: '8', name: 'Die kleine Stadtrunde', from: 'Hardplatz', to: 'Opernhaus', mode: 'tram', color: '#af7b9e', cost: 1800, level: 2, duration: 22, capacity: 28, fare: 5, points: [[-10,3],[-4,3],[-4,-3],[2,-3],[12,-3],[12,3]], stops: ['Hardplatz','Stauffacher','Kunsthaus','Opernhaus'] },
  { id: 's12', number: 'S12', name: 'Über die Stadt hinaus', from: 'Altstetten', to: 'Stadelhofen', mode: 'train', color: '#628cb0', cost: 2600, level: 3, duration: 24, capacity: 52, fare: 6, points: [[-14,-11],[-10,-11],[-4,-11],[2,-11],[8,-11],[14,-11]], stops: ['Altstetten','Hauptbahnhof','Stadelhofen'] },
  { id: 'm1', number: 'M1', name: 'Unterwegs im Untergrund', from: 'Universität', to: 'Seefeld', mode: 'metro', color: '#9a81b5', cost: 3800, level: 4, duration: 18, capacity: 64, fare: 6, points: [[-10,-9],[-10,-3],[-4,-3],[-4,3],[2,3],[2,9]], stops: ['Universität','Central','Paradeplatz','Seefeld'] },
  { id: 'l1', number: 'L1', name: 'Eine kleine Seereise', from: 'Landesmuseum', to: 'Zürichhorn', mode: 'ship', color: '#55a69e', cost: 5200, level: 5, duration: 28, capacity: 75, fare: 8, points: [[7.7,-9],[7.7,-3],[7.7,3],[7.7,9],[7.7,13]], stops: ['Landesmuseum','Bürkliplatz','Zürichhorn'] },
  { id: 'c1', number: 'C1', name: 'Hoch hinaus', from: 'Talstation', to: 'Uetliberg', mode: 'cable', color: '#859e54', cost: 7200, level: 6, duration: 16, capacity: 28, fare: 10, points: [[-7,-7],[-11,-11],[-15,-15]], stops: ['Talstation','Uetliberg'] },
  { id: 'a1', number: 'LX', name: 'Hallo, Welt!', from: 'Zürich Airport', to: 'International', mode: 'plane', color: '#d48da9', cost: 10000, level: 7, duration: 35, capacity: 160, fare: 12, points: [[-15,11],[-8,3],[0,-5],[9,-14],[16,-20]], stops: ['Zürich Airport','International'] },
];

export const cityFor = (id: string) => CITIES.find(c => c.id === id) ?? CITIES[0];
const CITY_TERMINALS: Record<string, string[]> = {
  bern: ['Bümpliz','Bahnhof Bern','Wabern','Zentrum Paul Klee','Zytglogge','Wankdorf'],
  paris: ['Montmartre','Gare du Nord','Bastille','Tour Eiffel','Châtelet','Opéra'],
  london: ['Camden','King’s Cross','Brixton','Greenwich','Waterloo','Westminster'],
  newyork: ['Harlem','Grand Central','Brooklyn','Queens','Times Square','Downtown'],
  tokyo: ['Shinjuku','Tokyo Station','Shibuya','Asakusa','Ginza','Ueno'],
  rio: ['Centro','Central do Brasil','Copacabana','Ipanema','Lapa','Botafogo'],
  sydney: ['Newtown','Central','Bondi','Circular Quay','Town Hall','Manly'],
};
export function routeInCity(route: Route, cityId: string): Route {
  const names = CITY_TERMINALS[cityId];
  if (!names) return route;
  const i = ROUTES.indexOf(route);
  const from = names[i % names.length];
  const to = names[(i + 1 + i % 3) % names.length];
  return { ...route, from, to, stops: [from, ...route.stops.slice(1,-1).map((_, j) => names[(i+j+2)%names.length]), to] };
}
export const levelFor = (xp: number) => Math.floor(Math.sqrt(Math.max(0, xp) / 90)) + 1;
export const xpFor = (level: number) => (level - 1) ** 2 * 90;
export const fmt = (n: number) => Math.floor(n).toLocaleString('de-CH');
export const upgradeCost = (route: Route, tier: number) => Math.round((route.cost || 400) * (0.55 + tier * 0.45));
export const allOwned = (s: GameState) => Object.values(s.cities).flatMap(c => c.routes);
export const incomePerMinute = (s: GameState, cityId = s.cityId) => Math.round((s.cities[cityId]?.routes ?? []).reduce((sum, own) => { const r = ROUTES.find(r => r.id === own.id)!; return sum + r.capacity * own.tier * r.fare * 60/r.duration; }, 0));
export const totalIncome = (s: GameState) => Object.keys(s.cities).reduce((n,id)=>n+incomePerMinute(s,id),0);

export function newGame(): GameState {
  return { version: 1, cash: 1200, xp: 0, passengers: 0, earned: 0, cityId: 'zurich', cities: { zurich: { routes: [{ id: 'b31', tier: 1, carried: 0, progress: 0 }] } }, claimed: [], seconds: 0, savedAt: Date.now(), settings: { sound: false, reducedMotion: false, night: false }, event: null, lastEvent: 0 };
}

export type Quest = { id: string; title: string; description: string; current: number; target: number; reward: number; xp: number; category: 'start' | 'network' | 'world' | 'daily' };
export function questsFor(s: GameState): Quest[] {
  const owned = allOwned(s);
  const date = new Date().toLocaleDateString('en-CA');
  const quests: Quest[] = [
    { id:'second', title:'Ein Netz entsteht', description:'Schalte eine zweite Linie frei.', current:owned.length, target:2, reward:650, xp:100, category:'start' },
    { id:'first50', title:'Die ersten 50', description:'Bringe 50 Menschen an ihr Ziel.', current:s.passengers, target:50, reward:400, xp:100, category:'start' },
    { id:'tram', title:'Wir bleiben auf Schienen', description:'Nimm deine erste Tramlinie in Betrieb.', current:owned.some(o=>ROUTES.find(r=>r.id===o.id)?.mode==='tram')?1:0, target:1, reward:900, xp:140, category:'network' },
    { id:'upgrade', title:'Bitte einsteigen!', description:'Baue eine Linie mit einem zweiten Fahrzeug aus.', current:owned.some(o=>o.tier>=2)?1:0, target:1, reward:650, xp:100, category:'network' },
    { id:'p500', title:'Die Stadt bewegt sich', description:'Befördere insgesamt 500 Fahrgäste.', current:s.passengers, target:500, reward:1800, xp:300, category:'network' },
    { id:'rail', title:'Nächster Halt: Fernweh', description:'Schalte eine Zuglinie frei.', current:owned.some(o=>ROUTES.find(r=>r.id===o.id)?.mode==='train')?1:0, target:1, reward:2200, xp:300, category:'network' },
    { id:'city2', title:'Über die Stadtgrenze', description:'Erschliesse eine zweite Stadt.', current:Object.keys(s.cities).length, target:2, reward:3000, xp:400, category:'world' },
    ...(['metro','ship','cable','plane'] as Mode[]).map((mode,i)=>({id:mode,title:MODES[mode].description, description:`Nimm deine erste ${MODES[mode].name === 'Flugzeug' ? 'Fluglinie' : MODES[mode].name+'linie'} in Betrieb.`,current:owned.some(o=>ROUTES.find(r=>r.id===o.id)?.mode===mode)?1:0,target:1,reward:3200+i*1200,xp:400+i*100,category:'network' as const})),
    { id:'p5000', title:'Eine Stadt, tausend Geschichten', description:'Befördere 5 000 Fahrgäste.', current:s.passengers, target:5000, reward:7500, xp:1200, category:'network' },
    { id:'world8', title:'Die Welt im Takt', description:'Erschliesse alle acht Städte.', current:Object.keys(s.cities).length, target:8, reward:25000, xp:3000, category:'world' },
    { id:`daily-${date}`, title:'Heute läuft’s rund', description:'Verdiene heute 5 000 Münzen. Einmal täglich.', current:s.earned-(dailyBaseline(s,date)), target:5000, reward:1500, xp:200, category:'daily' },
  ];
  return quests.map(q=>({...q,current:Math.min(q.target,Math.max(0,q.current))}));
}
// Daily baselines live inside the save, so reloads cannot reset a daily reward.
function dailyBaseline(s: GameState, date: string) {
  const marker = s.claimed.find(v=>v.startsWith(`baseline-${date}:`));
  const value = marker ? Number(marker.split(':')[1]) : s.earned;
  return Number.isFinite(value) && value >= 0 ? value : s.earned;
}

export type Action = { type:'tick'; dt:number } | { type:'buy'; id:string } | { type:'upgrade'; id:string } | { type:'claim'; id:string } | { type:'city'; id:string } | { type:'settings'; settings:Partial<Settings> } | { type:'reset' };
export function gameReducer(s: GameState, action: Action): GameState {
  if(action.type==='reset') return newGame();
  if(action.type==='settings') return {...s,settings:{...s.settings,...action.settings}};
  if(action.type==='buy') {
    const r=ROUTES.find(r=>r.id===action.id);
    if(!r || levelFor(s.xp)<r.level || s.cash<r.cost || s.cities[s.cityId].routes.some(o=>o.id===r.id)) return s;
    return {...s,cash:s.cash-r.cost,xp:s.xp+50,cities:{...s.cities,[s.cityId]:{routes:[...s.cities[s.cityId].routes,{id:r.id,tier:1,carried:0,progress:0}]}}};
  }
  if(action.type==='upgrade') {
    const city=s.cities[s.cityId]; const own=city.routes.find(o=>o.id===action.id); const r=ROUTES.find(r=>r.id===action.id);
    if(!own || !r || own.tier>=5) return s;
    const cost=upgradeCost(r,own.tier); if(s.cash<cost) return s;
    return {...s,cash:s.cash-cost,xp:s.xp+70,cities:{...s.cities,[s.cityId]:{routes:city.routes.map(o=>o.id===own.id?{...o,tier:o.tier+1}:o)}}};
  }
  if(action.type==='claim') {
    const q=questsFor(s).find(q=>q.id===action.id); if(!q || s.claimed.includes(q.id)||q.current<q.target) return s;
    return {...s,cash:s.cash+q.reward,xp:s.xp+q.xp,claimed:[...s.claimed,q.id]};
  }
  if(action.type==='city') {
    const c=CITIES.find(c=>c.id===action.id); if(!c) return s;
    if(s.cities[c.id]) return {...s,cityId:c.id};
    if(s.cash<c.cost || levelFor(s.xp)<c.level) return s;
    return {...s,cityId:c.id,cash:s.cash-c.cost,xp:s.xp+150,cities:{...s.cities,[c.id]:{routes:[{id:'b31',tier:1,carried:0,progress:0}]}}};
  }
  const dt=Number.isFinite(action.dt)?Math.min(5,Math.max(0,action.dt)):0;
  if(dt===0)return s;
  let passengers=0; let cash=0;
  const seconds=s.seconds+dt;
  let event=s.event && s.event.endsAt>seconds?s.event:null;
  let lastEvent=s.lastEvent;
  if(!event && seconds-lastEvent>=120) {event={kind:Math.floor(seconds/120)%2===0?'festival':'rush',endsAt:seconds+35};lastEvent=seconds;}
  const cities=Object.fromEntries(Object.entries(s.cities).map(([id,c])=>[id,{routes:c.routes.map(o=>{
    const r=ROUTES.find(r=>r.id===o.id)!;
    const progress=o.progress+dt;
    const trips=Math.floor(progress/r.duration);
    const carried=trips*r.capacity*o.tier;
    passengers+=carried; cash+=carried*r.fare*(event?1.5:1);
    return {...o,progress:progress%r.duration,carried:o.carried+carried};
  })}]));
  const date = new Date().toLocaleDateString('en-CA');
  const claimed=s.claimed.some(v=>v.startsWith(`baseline-${date}:`))?s.claimed:[...s.claimed.filter(v=>!v.startsWith('baseline-')),`baseline-${date}:${s.earned}`];
  return {...s,cities,seconds,event,lastEvent,cash:s.cash+cash,earned:s.earned+cash,passengers:s.passengers+passengers,xp:s.xp+Math.floor((s.passengers+passengers)/3)-Math.floor(s.passengers/3),claimed,savedAt:Date.now()};
}

export const SAVE_KEY='takt-save-v1';
export function parseSave(raw:string|null):GameState {
  if(!raw) return newGame();
  try {
    const s=JSON.parse(raw) as GameState;
    const finite=(v:unknown)=>typeof v==='number'&&Number.isFinite(v)&&v>=0;
    if(s.version!==1 || ![s.cash,s.xp,s.passengers,s.earned,s.seconds,s.savedAt,s.lastEvent].every(finite) || !Array.isArray(s.claimed) || !s.claimed.every(v=>typeof v==='string') || !s.cities || !s.cities[s.cityId] || !s.cities.zurich || !s.settings || typeof s.settings.sound!=='boolean' || typeof s.settings.night!=='boolean' || typeof s.settings.reducedMotion!=='boolean') return newGame();
    for(const [id,c] of Object.entries(s.cities)) {
      if(!CITIES.some(c=>c.id===id)||!Array.isArray(c.routes)||!c.routes.length||new Set(c.routes.map(r=>r.id)).size!==c.routes.length) return newGame();
      if(c.routes.some(o=>!ROUTES.some(r=>r.id===o.id)||!Number.isInteger(o.tier)||o.tier<1||o.tier>5||!finite(o.carried)||!finite(o.progress)||o.progress>=(ROUTES.find(r=>r.id===o.id)?.duration??0))) return newGame();
    }
    if(s.event && (!['rush','festival'].includes(s.event.kind)||!finite(s.event.endsAt))) return newGame();
    return s;
  } catch { return newGame(); }
}
