import { useEffect, useReducer, useRef, useState } from 'react';
import { ArrowDownLeft, ArrowRight, ArrowUpRight, Bell, Bus, CableCar, Check, CheckCheck, ChevronDown, ChevronRight, CircleHelp, Coins, Compass, Download, Flag, Globe2, Heart, Leaf, LockKeyhole, Map, MapPin, Maximize, Minus, Moon, Pause, Plane, Play, Plus, RotateCcw, Route as RouteIcon, Settings2, Ship, Sparkles, Sun, Target, TrainFront, TramFront, TrendingUp, Trophy, Users, Volume2, VolumeX, X, Zap } from 'lucide-react';
import type { LucideIcon } from 'lucide-react';
import CityScene from './CityScene';
import type { SceneHandle } from './CityScene';
import { CITIES, MODES, ROUTES, SAVE_KEY, allOwned, cityFor, fmt, gameReducer, incomePerMinute, levelFor, parseSave, questsFor, routeInCity, totalIncome, upgradeCost, xpFor } from './game';
import type { Mode, Quest, Route } from './game';
import '@fontsource-variable/dm-sans';
import '@fontsource-variable/manrope';

const ModeIcon:Record<Mode,LucideIcon>={bus:Bus,tram:TramFront,train:TrainFront,metro:TrainFront,ship:Ship,plane:Plane,cable:CableCar};
type Panel = 'lines'|'fleet'|'world'|'quests'|'settings'|'help'|null;
type Toast = { id:number; text:string; kind:'success'|'info' };
const TITLES: Record<NonNullable<Panel>,string>={lines:'Jede Linie verbindet.',fleet:'Kleine Flotte. Grosse Pläne.',world:'Nächster Halt: die Welt.',quests:'Ein Ziel vor Augen.',settings:'Ganz in deinem Takt.',help:'Willkommen an Bord.'};
const DESCRIPTIONS:Record<NonNullable<Panel>,string>={lines:'Entdecke feste Strecken, schalte sie frei und bring deine Stadt in Bewegung.',fleet:'Vom ersten Quartierbus bis zum Flugzeug. Dein Netz wächst mit dir.',world:'Alles beginnt in Zürich. Wohin führt dich dein Verkehrsnetz als Nächstes?',quests:'Bewege etwas. Schliesse Aufgaben ab und hole dir deine Belohnungen.',settings:'Dein Spielstand wird automatisch auf diesem Gerät gespeichert.',help:'Deine erste Linie fährt schon. Jetzt liegt die Stadt in deinen Händen.'};

function loadGame(){try{return parseSave(localStorage.getItem(SAVE_KEY));}catch{return parseSave(null);}}
function chime(){
  try{const context=new AudioContext();const gain=context.createGain();gain.gain.setValueAtTime(.035,context.currentTime);gain.gain.exponentialRampToValueAtTime(.001,context.currentTime+.45);gain.connect(context.destination);[523.25,659.25,783.99].forEach((f,i)=>{const o=context.createOscillator();o.type='sine';o.frequency.value=f;o.connect(gain);o.start(context.currentTime+i*.075);o.stop(context.currentTime+.5);});setTimeout(()=>void context.close(),700);}catch{/* Sound is optional on devices that restrict audio. */}
}

export default function App(){
  const [state,dispatch]=useReducer(gameReducer,undefined,loadGame);
  const [panel,setPanel]=useState<Panel>(null);
  const [filter,setFilter]=useState<Mode|'all'>('all');
  const [selected,setSelected]=useState<string|null>(null);
  const [speed,setSpeed]=useState(1);
  const [toasts,setToasts]=useState<Toast[]>([]);
  const [saveError,setSaveError]=useState(false);
  const [resetConfirm,setResetConfirm]=useState(false);
  const [questFilter,setQuestFilter]=useState<'open'|'done'>('open');
  const [worldCity,setWorldCity]=useState('bern');
  const [notice,setNotice]=useState(false);
  const sceneRef=useRef<SceneHandle|null>(null);
  const stateRef=useRef(state);stateRef.current=state;
  const level=levelFor(state.xp);
  const previousLevel=useRef(level);
  const modalRef=useRef<HTMLDivElement>(null);
  const previousFocus=useRef<HTMLElement|null>(null);
  const city=cityFor(state.cityId);
  const owned=state.cities[state.cityId].routes;
  const quests=questsFor(state);
  const openQuests=quests.filter(q=>!state.claimed.includes(q.id));
  const readyQuests=openQuests.filter(q=>q.current>=q.target);
  const nextQuest=readyQuests[0]??openQuests[0];
  const xpProgress=(state.xp-xpFor(level))/(xpFor(level+1)-xpFor(level))*100;
  const addToast=(text:string,kind:Toast['kind']='success')=>{
    const id=Date.now()+Math.random();setToasts(t=>[...t.slice(-2),{id,text,kind}]);
    window.setTimeout(()=>setToasts(t=>t.filter(v=>v.id!==id)),4600);
    if(kind==='success'&&stateRef.current.settings.sound)chime();
  };

  useEffect(()=>{
    let last=performance.now();
    const timer=setInterval(()=>{const now=performance.now();const dt=(now-last)/1000;last=now;if(!document.hidden&&speed>0)dispatch({type:'tick',dt:dt*speed});},1000);
    return()=>clearInterval(timer);
  },[speed]);
  useEffect(()=>{
    const persist=()=>{try{localStorage.setItem(SAVE_KEY,JSON.stringify({...stateRef.current,savedAt:Date.now()}));setSaveError(false);}catch{setSaveError(true);}};
    const timer=setInterval(persist,4000);window.addEventListener('pagehide',persist);
    const onVisibility=()=>{if(document.hidden)persist();};document.addEventListener('visibilitychange',onVisibility);
    return()=>{clearInterval(timer);window.removeEventListener('pagehide',persist);document.removeEventListener('visibilitychange',onVisibility);persist();};
  },[]);
  useEffect(()=>{
    // Purchases and rewards are persisted immediately, even when the app is closed quickly.
    try{localStorage.setItem(SAVE_KEY,JSON.stringify(state));}catch{setSaveError(true);}
  },[state]);
  useEffect(()=>{
    if(level>previousLevel.current){
      const unlocked=Object.values(MODES).find(m=>m.level===level);
      addToast(`Level ${level}! ${unlocked?unlocked.name+' ist jetzt verfügbar.':'Dein Verkehrsnetz wächst.'}`);
    }
    previousLevel.current=level;
  },[level]);
  useEffect(()=>{
    if(!panel)return;
    previousFocus.current=document.activeElement as HTMLElement;
    const previousOverflow=document.body.style.overflow;document.body.style.overflow='hidden';
    const timer=window.setTimeout(()=>modalRef.current?.querySelector<HTMLButtonElement>('button')?.focus(),20);
    const key=(e:KeyboardEvent)=>{
      if(e.key==='Escape'){setPanel(null);setResetConfirm(false);}
      if(e.key==='Tab'){
        const nodes=modalRef.current?.querySelectorAll<HTMLElement>('button:not(:disabled),input,select,[tabindex="0"],a[href]');
        if(!nodes?.length)return;const first=nodes[0],last=nodes[nodes.length-1];
        if(e.shiftKey&&document.activeElement===first){e.preventDefault();last.focus();}
        else if(!e.shiftKey&&document.activeElement===last){e.preventDefault();first.focus();}
      }
    };
    window.addEventListener('keydown',key);
    return()=>{window.clearTimeout(timer);document.body.style.overflow=previousOverflow;window.removeEventListener('keydown',key);previousFocus.current?.focus();};
  },[panel]);

  const showPanel=(p:Panel)=>{setPanel(p);setNotice(false);setResetConfirm(false);if(p==='lines')setFilter('all');};
  const buy=(r:Route)=>{
    if(level<r.level)return addToast(`Diese Linie wird ab Level ${r.level} verfügbar.`,'info');
    if(state.cash<r.cost)return addToast(`Dir fehlen noch ${fmt(r.cost-state.cash)} Münzen.`,'info');
    dispatch({type:'buy',id:r.id});setSelected(r.id);addToast(`Linie ${r.number} fährt jetzt. Gute Fahrt!`);
  };
  const upgrade=(r:Route)=>{
    const o=owned.find(o=>o.id===r.id);if(!o)return;
    const cost=upgradeCost(r,o.tier);if(state.cash<cost)return addToast(`Dir fehlen noch ${fmt(cost-state.cash)} Münzen.`,'info');
    dispatch({type:'upgrade',id:r.id});addToast(`Linie ${r.number}: ${o.tier+1} Fahrzeuge im Einsatz.`);
  };
  const claim=(q:Quest)=>{dispatch({type:'claim',id:q.id});addToast(`„${q.title}“ geschafft! +${fmt(q.reward)} Münzen und +${q.xp} XP.`);};
  const visitCity=(id:string)=>{
    const c=cityFor(id);
    if(!state.cities[id]&&(level<c.level||state.cash<c.cost))return;
    const existed=Boolean(state.cities[id]);dispatch({type:'city',id});setPanel(null);setSelected(null);addToast(existed?`Willkommen zurück in ${c.name}.`:`Hallo, ${c.name}! Deine erste Buslinie fährt bereits.`);
  };
  const exportSave=()=>{
    const blob=new Blob([JSON.stringify(state,null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download=`takt-spielstand-${new Date().toISOString().slice(0,10)}.json`;a.click();URL.revokeObjectURL(url);addToast('Dein Spielstand wurde exportiert.');
  };
  const importSave=async(file:File)=>{
    if(file.size>1024*1024)return addToast('Diese Datei ist zu gross. Bitte wähle einen Takt-Spielstand.','info');
    try{
      const raw=await file.text();const parsed=parseSave(raw);
      if(JSON.stringify(parsed)!==JSON.stringify(JSON.parse(raw)))return addToast('Dieser Spielstand ist ungültig. Dein aktueller Stand bleibt erhalten.','info');
      localStorage.setItem(SAVE_KEY,raw);window.location.reload();
    }catch{addToast('Die Datei konnte nicht als Spielstand gelesen werden.','info');}
  };
  const focusRoute=(id:string)=>{setSelected(id);sceneRef.current?.focus(id);setPanel(null);};
  const navItems:{panel:Panel;icon:LucideIcon;label:string;badge?:string|number}[]=[
    {panel:null,icon:Map,label:'Meine Stadt'},
    {panel:'lines',icon:RouteIcon,label:'Liniennetz',badge:owned.length},
    {panel:'fleet',icon:Bus,label:'Verkehrsmittel'},
    {panel:'world',icon:Globe2,label:'Welt entdecken'},
    {panel:'quests',icon:Target,label:'Aufgaben',badge:readyQuests.length||undefined},
  ];
  const selectedRoute=ROUTES.find(r=>r.id===selected);
  const selectedOwn=owned.find(o=>o.id===selected);

  return <div className={`app ${state.settings.night?'night':''} ${state.settings.reducedMotion?'reduce-motion':''}`}>
    <aside className="sidebar" inert={Boolean(panel)}>
      <button className="brand" onClick={()=>showPanel(null)} aria-label="Takt Startseite"><span className="brand-mark"><svg viewBox="0 0 32 36" fill="none"><path d="M9 3v24c0 8 10 8 10 0V11c0-8 10-8 10 0v24M2 12h13M23 25h9" stroke="currentColor" strokeWidth="3.6" strokeLinecap="round"/></svg></span><span>takt<span className="brand-period">.</span></span></button>
      <div className="sidebar-caption">DEINE STADT. DEIN NETZ.</div>
      <div className="nav-label">DEIN IMPERIUM</div>
      <nav className="main-nav" aria-label="Hauptnavigation">{navItems.map(n=><button key={n.label} className={`nav-item ${panel===n.panel?'active':''}`} onClick={()=>showPanel(n.panel)}><n.icon size={20}/><span>{n.label}</span>{n.badge!==undefined&&<span className={`nav-badge ${n.panel==='quests'?'coral':''}`}>{n.badge}</span>}</button>)}</nav>
      <div className="sidebar-world" onClick={()=>showPanel('world')} role="button" tabIndex={0} onKeyDown={e=>{if(e.key==='Enter')showPanel('world');}}>
        <div className="world-orbit"><Globe2 size={49} strokeWidth={1}/><span className="orbit-dot"/></div>
        <span className="eyebrow">KLEIN ANFANGEN.</span><h3>Gross rauskommen.</h3><p>Eine Stadt ist erst<br/>der Anfang.</p><span className="text-link">Entdecke die Welt <ArrowUpRight size={15}/></span>
      </div>
      <div className="sidebar-bottom">
        <button className="help-button" onClick={()=>showPanel('help')}><CircleHelp size={18}/> So funktioniert’s <ArrowUpRight size={14}/></button>
        <button className="player-card" onClick={()=>showPanel('quests')}><span className="player-avatar"><Leaf size={21}/></span><div><strong>Netz-Pionier</strong><span>Level {level} <span className="player-xp">{fmt(state.xp)} XP</span></span><div className="mini-progress"><i style={{width:`${xpProgress}%`}}/></div></div><ChevronRight size={15}/></button>
      </div>
    </aside>

    <main className="main-content" inert={Boolean(panel)}>
      <header className="topbar"><div className="breadcrumb">Dein Imperium <ChevronRight size={13}/><span>{city.name}</span><span className="beta-tag">BETA 0.1</span></div><div className="topbar-actions"><span className="save-indicator"><i/>{saveError?'Speichern nicht möglich':'Automatisch gespeichert'}</span><button className="icon-btn sound-top" aria-label={state.settings.sound?'Ton ausschalten':'Ton einschalten'} onClick={()=>dispatch({type:'settings',settings:{sound:!state.settings.sound}})}>{state.settings.sound?<Volume2 size={18}/>:<VolumeX size={18}/>}</button><button className="icon-btn notification" aria-label="Benachrichtigungen" onClick={()=>setNotice(n=>!n)}><Bell size={18}/>{readyQuests.length>0&&<i/>}</button><button className="icon-btn" aria-label="Einstellungen" onClick={()=>showPanel('settings')}><Settings2 size={18}/></button></div>
      {notice&&<div className="notice-popover"><strong>Dein Netz meldet sich</strong>{readyQuests.length?<><p>{readyQuests.length} {readyQuests.length===1?'Aufgabe ist':'Aufgaben sind'} geschafft. Deine Belohnung wartet!</p><button className="text-link" onClick={()=>showPanel('quests')}>Belohnungen abholen <ArrowRight size={15}/></button></>:<p>Alles fährt nach Plan. Schliesse Aufgaben ab, um neue Verkehrsmittel freizuschalten.</p>}</div>}</header>

      <section className="city-header">
        <div><div className="eyebrow greeting"><span className="swiss-flag">{city.flag === 'CH' ? '✚' : city.flag}</span> DEIN KLEINES VERKEHRSIMPERIUM</div><button className="city-title" onClick={()=>showPanel('world')}><h1>{city.name}</h1><ChevronDown size={23}/></button><p>Einsteigen. Verbinden. Weiterdenken.</p></div>
        <div className="stats-row"><div className="stat-item"><span className="stat-icon money"><Coins size={21}/></span><div><span>Dein Guthaben</span><strong data-testid="cash">{fmt(state.cash)} <small>₮</small></strong></div><span className="income-label"><TrendingUp size={12}/> +{fmt(totalIncome(state))}/Min.</span></div><div className="stat-item"><span className="stat-icon people"><Users size={21}/></span><div><span>Fahrgäste gesamt</span><strong data-testid="passengers">{fmt(state.passengers)}</strong></div></div><div className="stat-item happiness"><span className="stat-icon happy"><Heart size={21}/></span><div><span>Zufriedenheit</span><strong>{Math.min(99,82+owned.length*2+owned.reduce((v,o)=>v+o.tier-1,0))}<small>%</small></strong></div></div></div>
      </section>

      <div className="game-layout">
        <section className="city-card" aria-label="Deine animierte Stadt">
          <div className="map-top"><span className="live-badge"><i/> DEINE STADT LEBT</span><span className="weather">{state.settings.night?<Moon size={17}/>:<Sun size={18}/>}<span className="weather-description">{state.settings.night?'Eine ruhige Nacht':'Ein guter Tag zum Verbinden'}</span><span className="weather-divider"/><span className="day-label">Tag {Math.floor(state.seconds/240)+1}</span></span></div>
          <CityScene state={state} speed={speed} selected={selected} onSelect={setSelected} sceneRef={sceneRef}/>
          <div className="map-location"><MapPin size={13}/>{city.name}, {city.country}<span>MINIATURWELT</span></div>
          <div className="map-controls"><button aria-label="Ansicht vergrössern" onClick={()=>sceneRef.current?.zoom(.2)}><Plus size={18}/></button><button aria-label="Ansicht verkleinern" onClick={()=>sceneRef.current?.zoom(-.2)}><Minus size={18}/></button><span/><button aria-label="Kamera zurücksetzen" onClick={()=>sceneRef.current?.reset()}><Maximize size={16}/></button><button aria-label={state.settings.night?'Tag einschalten':'Nacht einschalten'} onClick={()=>dispatch({type:'settings',settings:{night:!state.settings.night}})}>{state.settings.night?<Sun size={17}/>:<Moon size={17}/>}</button></div>
          {state.event&&<div className="event-banner"><Zap size={17}/><span><strong>{state.event.kind==='rush'?'Feierabendverkehr!':'Stadtfest!'}</strong> +50 % Einnahmen · noch {Math.ceil(state.event.endsAt-state.seconds)}s Spielzeit</span></div>}
          {selectedRoute&&selectedOwn&&<div className="selected-route-card"><div className="selected-line-top"><span className="route-number" style={{background:selectedRoute.color}}>{selectedRoute.number}</span><strong>{MODES[selectedRoute.mode].name} · {routeInCity(selectedRoute,state.cityId).from}</strong><button className="icon-btn" aria-label="Linienauswahl schliessen" onClick={()=>setSelected(null)}><X size={15}/></button></div><p>{routeInCity(selectedRoute,state.cityId).from} <ArrowRight size={12}/> {routeInCity(selectedRoute,state.cityId).to}</p><div className="selected-line-bottom"><span><Users size={13}/>{fmt(selectedOwn.carried)} befördert</span><button onClick={()=>showPanel('lines')}>Linie verwalten <ArrowRight size={13}/></button></div></div>}
          <div className="map-bottom"><div className="map-status"><span className="status-icon"><Leaf size={15}/></span><div><strong>{speed===0?'Ein Moment zum Durchatmen.':'Alles im grünen Bereich.'}</strong><span>{owned.length} {owned.length===1?'Linie bewegt':'Linien bewegen'} deine Stadt.</span></div></div><button className="primary-button build-button" onClick={()=>showPanel('lines')}><Plus size={18}/> Linie freischalten <span><ArrowUpRight size={16}/></span></button></div>
        </section>

        <aside className="city-aside">
          <section className="quest-spotlight"><div className="section-heading"><span className="eyebrow">DER WEG IST DAS ZIEL</span><span className="quest-spark"><Sparkles size={16}/></span></div><div className="quest-illustration"><span className="quest-ring ring-one"/><span className="quest-ring ring-two"/><Flag size={31} strokeWidth={1.7}/><span className="quest-star">✦</span><span className="quest-dot"/></div><span className="quest-kicker">DEIN NÄCHSTER MEILENSTEIN</span><h2>{nextQuest?.title??'Die Welt liegt dir zu Füssen.'}</h2><p>{nextQuest?.description??'Alle Meilensteine geschafft. Erweitere dein Netz und komm morgen für deine Tagesaufgabe wieder.'}</p>{nextQuest&&<><div className="quest-progress-label"><span>{nextQuest.current>=nextQuest.target?'Geschafft! Gut verbunden.':'Schritt für Schritt'}</span><strong>{fmt(nextQuest.current)}<span> / {fmt(nextQuest.target)}</span></strong></div><div className="progress-track"><i style={{width:`${nextQuest.current/nextQuest.target*100}%`}}/></div><div className="quest-reward"><span><Coins size={16}/> +{fmt(nextQuest.reward)}</span><span><Sparkles size={14}/> +{nextQuest.xp} XP</span></div><button className={`quest-button ${nextQuest.current>=nextQuest.target?'ready':''}`} onClick={()=>nextQuest.current>=nextQuest.target?claim(nextQuest):showPanel('quests')}>{nextQuest.current>=nextQuest.target?'Belohnung abholen':'Alle Aufgaben ansehen'}{nextQuest.current>=nextQuest.target?<Check size={16}/>:<ArrowRight size={16}/>}</button></>}</section>
          <section className="network-preview"><div className="section-heading"><h3>Deine Linien</h3><span className="count-pill">{owned.length} aktiv</span></div><div className="preview-line-list">{owned.slice(0,3).map(o=>{const r=routeInCity(ROUTES.find(r=>r.id===o.id)!,state.cityId);const Icon=ModeIcon[r.mode];return <button className={`preview-line ${selected===r.id?'selected':''}`} key={o.id} onClick={()=>focusRoute(o.id)}><span className="line-mode" style={{color:r.color,background:r.color+'18'}}><Icon size={20}/></span><span className="preview-line-text"><strong><span style={{color:r.color}}>{r.number}</span> {r.from}</strong><span>{r.to} <span className="small-dot"/> {o.tier} {o.tier===1?'Fahrzeug':'Fahrzeuge'}</span></span><ChevronRight size={15}/></button>;})}</div>{owned.length<ROUTES.length&&<button className="add-line-ghost" onClick={()=>showPanel('lines')}><Plus size={19}/><span>Platz für neue Verbindungen</span></button>}<button className="text-link all-lines" onClick={()=>showPanel('lines')}>Zum Liniennetz <ArrowRight size={14}/></button></section>
          <div className="little-note"><span>✦</span><p>Hinter jeder Fahrt steckt<br/>eine kleine Geschichte.</p></div>
        </aside>
      </div>

      <section className="fleet-strip"><div className="fleet-intro"><span className="eyebrow">DEIN FUHRPARK</span><h3>Was bewegt dich?</h3><button className="text-link" onClick={()=>showPanel('fleet')}>Alle entdecken <ArrowUpRight size={13}/></button></div><div className="fleet-items">{(Object.entries(MODES) as [Mode,typeof MODES[Mode]][]).map(([mode,m])=>{const Icon=ModeIcon[mode];const available=level>=m.level;const active=owned.filter(o=>ROUTES.find(r=>r.id===o.id)?.mode===mode).length;return <button className={`fleet-item ${!available?'locked':''} ${active?'in-use':''}`} key={mode} onClick={()=>{setFilter(mode);setPanel('lines');}}><div className="fleet-icon" style={{'--mode-color':m.color} as React.CSSProperties}><Icon size={30} strokeWidth={1.5}/>{!available&&<span className="tiny-lock"><LockKeyhole size={10}/></span>}{active>0&&<span className="available-dot"/>}</div><strong>{m.name}</strong><span>{active?`${active} ${active===1?'Linie':'Linien'} aktiv`:available?'Bereit für dich':`Ab Level ${m.level}`}</span></button>;})}</div><div className="fleet-next"><span className="level-token">{level+1}</span><span>Nächster Halt<br/><strong>Level {level+1}</strong></span><div className="small-level-ring"><svg viewBox="0 0 40 40"><circle cx="20" cy="20" r="16"/><circle cx="20" cy="20" r="16" pathLength="100" style={{strokeDasharray:`${xpProgress} 100`}}/></svg><span>{Math.round(xpProgress)}%</span></div></div></section>

      <footer className="game-footer"><span><i/> {speed===0?'Simulation pausiert':'Entspannt aufbauen. Grosses bewegen.'}</span><div className="speed-controls"><span>DEIN TAKT</span><button aria-label={speed===0?'Spiel fortsetzen':'Spiel pausieren'} onClick={()=>setSpeed(speed===0?1:0)}>{speed===0?<Play size={13}/>:<Pause size={13}/>}</button>{[1,2,3].map(s=><button key={s} className={speed===s?'active':''} aria-label={`${s}-fache Geschwindigkeit`} onClick={()=>setSpeed(s)}>{s}×</button>)}</div><span className="footer-tip">Ziehen zum Drehen · Scrollen zum Zoomen</span></footer>
    </main>

    <nav className="mobile-nav" aria-label="Mobile Navigation" inert={Boolean(panel)}>{navItems.map(n=><button key={n.label} className={panel===n.panel?'active':''} onClick={()=>showPanel(n.panel)} aria-label={n.label}><n.icon size={21}/><span>{n.panel==='fleet'?'Flotte':n.panel==='world'?'Welt':n.panel==='lines'?'Linien':n.panel==='quests'?'Aufgaben':'Stadt'}</span>{n.panel==='quests'&&readyQuests.length>0&&<i/>}</button>)}</nav>

    {panel&&<div className="modal-overlay" onMouseDown={e=>{if(e.target===e.currentTarget)setPanel(null);}}><div className={`modal ${panel==='world'?'world-modal':''}`} ref={modalRef} role="dialog" aria-modal="true" aria-labelledby="modal-title"><div className="modal-header"><div><span className="eyebrow">TAKT · {panel==='world'?'DEIN IMPERIUM':city.name.toUpperCase()}</span><h2 id="modal-title">{TITLES[panel]}</h2><p>{DESCRIPTIONS[panel]}</p></div><button className="close-button" aria-label="Fenster schliessen" onClick={()=>setPanel(null)}><X size={21}/></button></div>

      {panel==='lines'&&<><div className="modal-summary"><span><RouteIcon size={16}/><strong>{owned.length}</strong> aktive Linien</span><span><TrendingUp size={16}/><strong>{fmt(incomePerMinute(state))}</strong> Münzen/Min.</span><span className="budget"><Coins size={16}/>{fmt(state.cash)}</span></div><div className="filter-tabs" aria-label="Verkehrsmittel filtern"><button className={filter==='all'?'active':''} onClick={()=>setFilter('all')}>Alle Linien</button>{(Object.entries(MODES) as [Mode,typeof MODES[Mode]][]).map(([m,v])=>{const Icon=ModeIcon[m];return <button key={m} className={filter===m?'active':''} onClick={()=>setFilter(m)}><Icon size={15}/>{v.name}</button>;})}</div><div className="route-catalog">{ROUTES.filter(r=>filter==='all'||r.mode===filter).map(base=>{
        const r=routeInCity(base,state.cityId);const own=owned.find(o=>o.id===r.id);const locked=level<r.level;const Icon=ModeIcon[r.mode];
        return <article className={`route-card ${locked?'level-locked':''} ${own?'owned':''}`} key={r.id}><div className="route-card-top"><span className="route-number" style={{background:r.color}}>{r.number}</span><span className="route-mode-name"><Icon size={14}/>{MODES[r.mode].name}</span><span className={`route-status ${own?'operating':''}`}>{own?<><i/>In Betrieb</>:locked?<><LockKeyhole size={11}/>Level {r.level}</>:'Neue Verbindung'}</span></div><h3>{r.name}</h3><div className="route-endpoints"><span className="endpoint-dot" style={{borderColor:r.color}}/><strong>{r.from}</strong><span className="endpoint-track"/><strong>{r.to}</strong><span className="endpoint-dot filled" style={{background:r.color,borderColor:r.color}}/></div><div className="route-stops">{r.stops.join(' · ')}</div><div className="route-facts"><span><MapPin size={13}/>{r.stops.length} Haltestellen</span><span><Users size={13}/>{r.capacity*(own?.tier??1)} / Fahrt</span><span><Coins size={13}/>{fmt(r.capacity*(own?.tier??1)*r.fare*60/r.duration)}/Min.</span></div>{own?<div className="route-card-actions"><button className="secondary-button" onClick={()=>focusRoute(r.id)}><Compass size={15}/>Ansehen</button><button className="primary-button" disabled={own.tier>=5||state.cash<upgradeCost(r,own.tier)} onClick={()=>upgrade(r)}>{own.tier>=5?<><CheckCheck size={15}/>Voll ausgebaut</>:<><Plus size={15}/>Fahrzeug <span className="button-price">{fmt(upgradeCost(r,own.tier))} ₮</span></>}</button><span className="fleet-tier">{own.tier}/5 Fahrzeuge</span></div>:<button className="primary-button unlock-route" disabled={locked||state.cash<r.cost} onClick={()=>buy(r)}>{locked?<><LockKeyhole size={15}/>Ab Level {r.level}</>:<><Plus size={16}/>Linie freischalten<span className="button-price">{fmt(r.cost)} ₮</span></>}</button>}</article>;
      })}</div><div className="modal-footnote"><CircleHelp size={14}/>Alle Strecken und Haltestellen sind festgelegt. Zusätzliche Fahrzeuge erhöhen die Kapazität und deine Einnahmen.</div></>}

      {panel==='fleet'&&<div className="vehicle-catalog">{(Object.entries(MODES) as [Mode,typeof MODES[Mode]][]).map(([mode,m])=>{const Icon=ModeIcon[mode];const unlocked=level>=m.level;const count=allOwned(state).filter(o=>ROUTES.find(r=>r.id===o.id)?.mode===mode).reduce((n,o)=>n+o.tier,0);return <button key={mode} className={`vehicle-card ${!unlocked?'locked':''}`} onClick={()=>{setFilter(mode);setPanel('lines');}}><div className="vehicle-drawing" style={{'--mode-color':m.color} as React.CSSProperties}><span className="vehicle-ground"/><Icon size={74} strokeWidth={1.15}/><span className="vehicle-speed-line line-a"/><span className="vehicle-speed-line line-b"/></div><span className="vehicle-unlock">{unlocked?<><Check size={12}/>Freigeschaltet</>:<><LockKeyhole size={12}/>Level {m.level}</>}</span><h3>{m.name}</h3><p>{m.description}</p><div className="vehicle-card-footer"><span>{count?`${count} ${count===1?'Fahrzeug':'Fahrzeuge'} im Imperium`:unlocked?'Deine nächste Verbindung wartet':`${fmt(Math.max(0,xpFor(m.level)-state.xp))} XP bis zur Freischaltung`}</span><ArrowUpRight size={17}/></div></button>;})}<div className="vehicle-catalog-note"><Sparkles size={23}/><h3>Jede Fahrt bringt dich weiter.</h3><p>Sammle XP mit Fahrgästen und Aufgaben. Ein neues Level eröffnet dir neue Möglichkeiten.</p></div></div>}

      {panel==='quests'&&<><div className="quests-level"><div className="level-emblem"><Trophy size={25}/><span>{level}</span></div><div><div className="level-progress-top"><strong>Netz-Pionier · Level {level}</strong><span>{fmt(state.xp-xpFor(level))} / {fmt(xpFor(level+1)-xpFor(level))} XP</span></div><div className="progress-track"><i style={{width:`${xpProgress}%`}}/></div><p>Noch {fmt(xpFor(level+1)-state.xp)} XP bis Level {level+1}.</p></div></div><div className="quest-tabs"><button className={questFilter==='open'?'active':''} onClick={()=>setQuestFilter('open')}>Deine Aufgaben <span>{openQuests.length}</span></button><button className={questFilter==='done'?'active':''} onClick={()=>setQuestFilter('done')}>Geschafft <span>{quests.filter(q=>state.claimed.includes(q.id)).length}</span></button></div><div className="quest-list">{quests.filter(q=>questFilter==='done'?state.claimed.includes(q.id):!state.claimed.includes(q.id)).map(q=>{const ready=q.current>=q.target,done=state.claimed.includes(q.id);return <article className={`quest-row ${ready?'complete':''}`} key={q.id}><span className={`quest-type-icon ${done?'done':''}`}>{done?<CheckCheck size={22}/>:q.category==='world'?<Globe2 size={23}/>:q.category==='daily'?<Sun size={23}/>:<Flag size={23}/>}</span><div className="quest-row-info"><span className="eyebrow">{q.category==='daily'?'TAGESAUFGABE':q.category==='world'?'WELTENTDECKER':'MEILENSTEIN'}</span><h3>{q.title}</h3><p>{q.description}</p>{!done&&<div className="quest-row-progress"><div className="progress-track"><i style={{width:`${q.current/q.target*100}%`}}/></div><span>{fmt(q.current)} / {fmt(q.target)}</span></div>}</div><div className="quest-row-reward"><strong><Coins size={15}/>+{fmt(q.reward)}</strong><span>+{q.xp} XP</span>{done?<span className="claimed-text"><Check size={13}/>Abgeholt</span>:<button className={ready?'primary-button':'secondary-button'} disabled={!ready} onClick={()=>claim(q)}>{ready?'Abholen':'In Arbeit'}{ready&&<ArrowDownLeft size={14}/>}</button>}</div></article>;})}{questFilter==='done'&&!quests.some(q=>state.claimed.includes(q.id))&&<div className="empty-state"><Flag size={34}/><h3>Deine erste Geschichte wartet.</h3><p>Schliesse eine Aufgabe ab und hole die Belohnung ab. Dann findest du sie hier.</p><button className="primary-button" onClick={()=>setQuestFilter('open')}>Zu deinen Aufgaben <ArrowRight size={15}/></button></div>}</div></>}

      {panel==='world'&&<><div className="world-stats"><span><Globe2 size={16}/><strong>{Object.keys(state.cities).length}</strong> von 8 Städten entdeckt</span><span><TrendingUp size={16}/><strong>{fmt(totalIncome(state))}</strong> Münzen/Min. weltweit</span></div><div className="world-map"><svg viewBox="0 0 1000 470" className="continent-map" aria-hidden="true"><defs><pattern id="dots" width="14" height="14" patternUnits="userSpaceOnUse"><circle cx="3" cy="3" r="1.2" fill="#a7b6a0" opacity=".5"/></pattern></defs><rect width="1000" height="470" fill="url(#dots)"/><g fill="#c4d1b9" stroke="#e8eddf" strokeWidth="2"><path d="M85 92L126 61 179 54 217 79 265 65 304 99 282 126 310 142 283 167 242 170 236 202 210 220 193 193 165 170 130 152 113 123Z"/><path d="M233 225L271 208 303 225 328 260 323 301 297 339 279 386 253 411 247 356 231 312 214 272Z"/><path d="M332 43L378 31 390 73 361 98 334 88Z"/><path d="M436 97L466 68 491 74 516 59 549 85 539 107 570 124 551 150 510 147 488 174 461 155 434 133Z"/><path d="M470 170L512 159 550 180 577 221 552 256 538 304 506 330 479 303 473 258 449 221Z"/><path d="M547 86L606 58 664 67 706 52 778 69 813 102 879 102 917 144 886 178 841 176 821 210 786 227 751 202 723 245 688 218 664 171 620 160 591 138 562 148Z"/><path d="M751 260L775 247 802 267 827 265 851 292 830 304 796 292 778 288Z"/><path d="M836 332L876 315 913 326 941 366 918 392 869 390 838 366Z"/><path d="M955 394L967 382 973 417 958 437 945 429Z"/><path d="M886 193L897 173 903 195 893 212Z"/></g><path d="M490 146Q325 5 250 160M490 146Q720 2 870 183M490 146Q700 443 910 365M490 146Q362 154 340 333" fill="none" stroke="#9bb59b" strokeDasharray="5 6" strokeWidth="1.5" opacity=".65"/></svg>{CITIES.map(c=><button key={c.id} className={`world-pin ${state.cities[c.id]?'unlocked':''} ${worldCity===c.id?'selected':''}`} style={{left:`${c.x}%`,top:`${c.y}%`}} onClick={()=>setWorldCity(c.id)} aria-label={`${c.name}${state.cities[c.id]?', freigeschaltet':''}`}><span>{state.cities[c.id]?<MapPin size={14}/>:<LockKeyhole size={11}/>}</span><strong>{c.name}</strong></button>)}<span className="map-world-caption">EIN KLEINES NETZ. EINE GROSSE WELT.</span></div><div className="city-catalog">{CITIES.map(c=>{const unlocked=Boolean(state.cities[c.id]);const current=state.cityId===c.id;const accessible=level>=c.level;return <article key={c.id} className={`world-city-card ${worldCity===c.id?'highlighted':''} ${unlocked?'discovered':''}`} onMouseEnter={()=>setWorldCity(c.id)}><div className="city-postcard" style={{'--city-accent':c.accent} as React.CSSProperties}><CityPostcard cityId={c.id}/><span className="country-stamp">{c.flag}</span><span className="postcard-label">{c.country}</span></div><div className="city-postcard-info"><div className="city-card-heading"><h3>{c.name}</h3>{current?<span className="current-city">Du bist hier</span>:unlocked?<Check size={16}/>:<span className="city-level"><LockKeyhole size={11}/>Level {c.level}</span>}</div><p>{c.tagline}</p>{unlocked?<button className="secondary-button" disabled={current} onClick={()=>visitCity(c.id)}>{current?'Aktuelle Stadt':'Stadt besuchen'}{!current&&<ArrowRight size={15}/>}</button>:<button className="primary-button" disabled={!accessible||state.cash<c.cost} onClick={()=>visitCity(c.id)}>{accessible?'Stadt erschliessen':`Ab Level ${c.level}`}<span className="button-price">{fmt(c.cost)} ₮</span></button>}</div></article>;})}</div><div className="modal-footnote"><Globe2 size={14}/>Deine Linien in anderen Städten fahren weiter, solange das Spiel aktiv ist. Jede Stadt startet mit einer Buslinie.</div></>}

      {panel==='settings'&&<div className="settings-content"><div className="settings-section"><h3>Ein Spiel in deinem Rhythmus</h3><SettingRow icon={Volume2} title="Kleine Erfolgsmomente" description="Spiele einen Ton bei Belohnungen und Freischaltungen." checked={state.settings.sound} onChange={()=>dispatch({type:'settings',settings:{sound:!state.settings.sound}})}/><SettingRow icon={Moon} title="Abendstimmung" description="Erlebe deine Miniaturstadt im sanften Nachtlicht." checked={state.settings.night} onChange={()=>dispatch({type:'settings',settings:{night:!state.settings.night}})}/><SettingRow icon={Leaf} title="Ruhigere Animationen" description="Reduziert Umgebungsbewegungen. Fahrzeuge bleiben sichtbar." checked={state.settings.reducedMotion} onChange={()=>dispatch({type:'settings',settings:{reducedMotion:!state.settings.reducedMotion}})}/></div><div className="save-box"><span className="save-box-icon"><CheckCheck size={26}/></span><div><h3>{saveError?'Speicher ist nicht verfügbar':'Dein Fortschritt ist bei dir.'}</h3><p>{saveError?'Dein Browser blockiert den lokalen Speicher. Exportiere deinen Spielstand, bevor du das Fenster schliesst.':'Takt speichert automatisch auf diesem Gerät. Sichere deinen Spielstand als Datei, um ihn auf ein anderes Gerät mitzunehmen.'}</p><div className="save-buttons"><button className="secondary-button" onClick={exportSave}><Download size={15}/>Spielstand exportieren</button><label className="secondary-button import-button">Spielstand importieren<input type="file" accept=".json,application/json" onChange={e=>{const f=e.target.files?.[0];if(f)void importSave(f);e.target.value='';}}/></label></div></div></div><div className="reset-section"><div><h3>Noch einmal ganz von vorn?</h3><p>Das löscht deinen gesamten Fortschritt auf diesem Gerät.</p></div>{resetConfirm?<div className="reset-confirm"><button className="secondary-button" onClick={()=>setResetConfirm(false)}>Behalten</button><button className="danger-button" onClick={()=>{dispatch({type:'reset'});setSelected(null);setPanel(null);setSpeed(1);addToast('Ein frischer Start. Willkommen zurück in Zürich.');}}>Ja, Spielstand löschen</button></div>:<button className="reset-button" onClick={()=>setResetConfirm(true)}><RotateCcw size={14}/>Neu anfangen</button>}</div><div className="about-app"><span className="brand-word">takt.</span><span>Deine Stadt. Dein Netz.<br/>Version 0.1.0 · Spielbare Beta</span><span>Mit Liebe zum ÖV gebaut. <Heart size={13}/></span></div></div>}

      {panel==='help'&&<div className="help-content"><div className="help-hero"><span><Bus size={54} strokeWidth={1.2}/></span><div><h3>Dein erster Bus ist schon unterwegs.</h3><p>Lehne dich kurz zurück und schau zu, wie deine Miniaturstadt aufwacht. Oder mach gleich die nächste Verbindung möglich.</p></div></div>{[{icon:RouteIcon,title:'1. Feste Linien freischalten',text:'Öffne das Liniennetz und kaufe eine vorgegebene Strecke. Alle Haltestellen stehen bereits fest. Die Fahrzeuge fahren sofort los.'},{icon:Coins,title:'2. Menschen bewegen. Geld verdienen.',text:'Deine Linien bringen regelmässig Fahrgäste ans Ziel. Jede abgeschlossene Fahrt bringt Münzen und Erfahrung. Mit zusätzlichen Fahrzeugen fährt noch mehr mit.'},{icon:Flag,title:'3. Aufgaben abschliessen',text:'Hole dir deine Belohnungen im Aufgabenmenü ab. Mit XP steigst du im Level auf und schaltest Tram, Zug, Metro, Schiff, Seilbahn und Flugzeug frei.'},{icon:Globe2,title:'4. Über die Stadt hinauswachsen',text:'Erschliesse neue Städte auf der Weltkarte. Jede bekommt ihr eigenes Liniennetz. Alle erschlossenen Städte verdienen gleichzeitig Geld, solange das Spiel läuft.'}].map(s=><div className="help-step" key={s.title}><span><s.icon size={23}/></span><div><h3>{s.title}</h3><p>{s.text}</p></div></div>)}<div className="help-tips"><Compass size={20}/><p><strong>Entdecke jedes kleine Detail.</strong> Ziehe mit einem Finger zum Drehen. Nutze zwei Finger zum Zoomen und Verschieben. Tippe ein Fahrzeug an, um seine Linie zu sehen. Unten kannst du das Tempo ändern oder pausieren.</p></div><button className="primary-button help-start" onClick={()=>{setPanel('lines');setFilter('all');}}>Meine nächste Linie entdecken <ArrowRight size={17}/></button></div>}
    </div></div>}

    <div className="toast-stack" aria-live="polite" aria-atomic="false">{toasts.map(t=><div className={`toast ${t.kind}`} key={t.id}><span>{t.kind==='success'?<Check size={18}/>:<CircleHelp size={18}/>}</span><p>{t.text}</p><button aria-label="Meldung schliessen" onClick={()=>setToasts(v=>v.filter(x=>x.id!==t.id))}><X size={15}/></button></div>)}</div>
  </div>;
}

function SettingRow({icon:Icon,title,description,checked,onChange}:{icon:LucideIcon;title:string;description:string;checked:boolean;onChange:()=>void}){
  return <div className="setting-row"><span className="setting-icon"><Icon size={21}/></span><div><h4>{title}</h4><p>{description}</p></div><button className={`toggle ${checked?'on':''}`} role="switch" aria-checked={checked} aria-label={title} onClick={onChange}><i/></button></div>;
}

function CityPostcard({cityId}:{cityId:string}){
  const city=cityFor(cityId);
  return <svg viewBox="0 0 400 150" aria-hidden="true" className="postcard-art"><circle cx="320" cy="35" r="24" fill="#f7e8b9"/><path d="M0 114Q60 58 132 106T280 91T400 100V150H0Z" fill={city.accent} opacity=".3"/><path d="M0 131Q75 91 160 130T330 111T400 118V150H0Z" fill={city.accent} opacity=".4"/>{cityId==='paris'?<g fill="#716f62"><path d="M197 28L192 86 173 135H185L194 113H211L219 135H232L212 86 206 28Z"/><rect x="187" y="83" width="28" height="4"/><rect x="181" y="105" width="42" height="4"/></g>:cityId==='sydney'?<g fill="#f3eddd" stroke="#d9d6c7"><path d="M148 128Q171 109 159 69Q203 84 206 128Z"/><path d="M180 128Q208 109 210 49Q251 79 245 128Z"/><path d="M220 128Q252 114 262 79Q287 101 278 128Z"/></g>:cityId==='tokyo'?<g fill="#bb7c73"><path d="M204 20L181 133H188L206 55 224 133H231L209 20Z"/><path d="M193 68H219V73H193ZM185 102H226V108H185Z"/></g>:cityId==='london'?<g><path d="M186 134V52H205V134Z" fill="#b49c77"/><path d="M181 53L195 30 210 53Z" fill="#7b8b7e"/><circle cx="195" cy="67" r="7" fill="#f3ecd9"/><path d="M195 62V67H200" fill="none" stroke="#7b826f" strokeWidth="2"/></g>:cityId==='rio'?<g fill="#c0c1a7"><path d="M191 135L201 84H209L220 135Z"/><circle cx="205" cy="74" r="7"/><path d="M173 82H237V89H173Z"/></g>:<g>{[0,1,2,3,4,5].map((n)=><g key={n}><rect x={106+n*28} y={cityId==='newyork'?52+(n%3)*17:86+(n%3)*8} width="24" height="65" fill={['#d9cbb3','#eae0c8','#c2c3b3'][n%3]}/>{cityId!=='newyork'&&<path d={`M${104+n*28} ${86+(n%3)*8}l14 -16 14 16Z`} fill={n%2?'#ac8f79':'#ba967f'}/>}<rect x={113+n*28} y={cityId==='newyork'?65+(n%3)*17:100+(n%3)*8} width="5" height="8" fill="#8aaba8"/></g>)}</g>}<path d="M0 137H400V150H0Z" fill={city.accent} opacity=".55"/><g transform="translate(288,112)"><rect width="36" height="15" rx="3" fill="#dca55a"/><rect x="4" y="3" width="26" height="5" fill="#bdd0c6"/><circle cx="7" cy="16" r="3" fill="#657a68"/><circle cx="29" cy="16" r="3" fill="#657a68"/></g><g fill="#89a07a"><circle cx="65" cy="111" r="13"/><rect x="63" y="112" width="4" height="26"/><circle cx="353" cy="115" r="12"/><rect x="351" y="115" width="4" height="23"/></g></svg>;
}
