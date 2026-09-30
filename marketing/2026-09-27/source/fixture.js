// Development-only transport and representative data. Never loaded by fxmanifest.lua.
(() => {
  const nativeFetch = window.fetch.bind(window);
  window.GetParentResourceName = () => 'cortex-lib-preview';
  window.fetch = async (input, init) => {
    if (String(input).startsWith('https://cortex-lib-preview/')) {
      const route = String(input).split('/').pop();
      const payload = JSON.parse(init?.body || '{}');
      window.__demoCallbacks = [...(window.__demoCallbacks || []), { route, payload }];
      if(['radialClose','radialBack','radialClick'].includes(route))setTimeout(()=>send('radialHide',{session:payload.session}),0);
      if(route==='radialClick')setTimeout(()=>send('notify',{title:'Demo selection',description:'Selected '+payload.itemId+'. Gameplay belongs to the consumer resource.',type:'info',duration:4000}),0);
      return new Response(JSON.stringify({ok:true}), {headers:{'Content-Type':'application/json'}});
    }
    return nativeFetch(input, init);
  };
  const send = (action,data={}) => window.dispatchEvent(new MessageEvent('message',{data:{action,data}}));
  window.addEventListener('load', async () => {
    await document.fonts.ready;
    const style=document.createElement('style');style.textContent='body{background:#0b111b!important}';document.head.append(style);
    const scene = new URLSearchParams(location.search).get('scene') || 'notifications';
    window.__demoScene = scene;
    const session=1;
    setTimeout(() => {
      if(scene === 'notifications') {
        [['success','Vehicle stored','Your Sultan is safe in the garage.'],['info','New assignment','Meet your crew at the marina.'],['warning','Server restart','Find a safe place. Restart in 10 minutes.'],['error','Vehicle unavailable','Move closer to your vehicle and try again.']].forEach(([type,title,description],i)=>send('notify',{id:'demo-'+i,type,title,description,persistent:true,showDuration:false,position:'top-right'}));
      }
      if(scene === 'menus')send('menuOpen',{id:'garage',session,revision:1,title:'Vehicle garage',subtitle:'PILLBOX HILL',position:'top-left',options:[{label:'Karin Sultan RS',description:'Ready to drive. Select to take this vehicle out.',progress:86},{label:'Obey Tailgater S',description:'Four-door sports sedan.'},{label:'Vehicle access',values:['Personal','Crew','Everyone'],description:'Choose who can access your vehicle.'},{label:'Show vehicle markers',checked:true,description:'Display your parked vehicles on the map.'},{label:'Return to previous menu'}]});
      if(scene === 'radial')send('radialShow',{session,menuId:'vehicle',items:[{id:'engine',label:'Engine',icon:'⏻'},{id:'doors',label:'Doors',icon:'↔'},{id:'trunk',label:'Trunk',icon:'▣'},{id:'windows',label:'Windows',icon:'▱'},{id:'seat',label:'Change seat',icon:'⇄'},{id:'lock',label:'Lock vehicle',icon:'◆'}]});
      if(scene === 'dialogs')send('contextMenu',{session,title:'Create a crew',fields:[{type:'input',name:'name',label:'Crew name',required:true,placeholder:'Name your crew'},{type:'select',name:'activity',label:'Activity',options:['Street racing','Car meets','Exploration']},{type:'checkbox',name:'invites',label:'Allow member invites'}],values:{name:'Midnight Drivers',activity:'Car meets',invites:true},labels:{confirm:'CREATE CREW',cancel:'CANCEL'}});
      if(scene === 'settings')send('settingsOpen',{session,tabs:[{id:'interface',label:'Interface',fields:[{key:'scale',type:'slider',label:'Interface scale',description:'Adjust the size of shared UI elements.',min:75,max:150,step:5,section:'Appearance'},{key:'position',type:'select',label:'Notification position',options:[{value:'top-right',label:'Top right'},{value:'top-left',label:'Top left'},{value:'bottom-right',label:'Bottom right'}],section:'Notifications'},{key:'sound',type:'toggle',label:'Notification sounds',description:'Play a sound when a notification arrives.',section:'Notifications'},{key:'duration',type:'slider',label:'Display duration',min:2,max:10,step:1,suffix:'s',section:'Notifications'}],values:{scale:100,position:'top-right',sound:true,duration:5},defaults:{scale:100,position:'top-right',sound:true,duration:5}},{id:'accessibility',label:'Accessibility',fields:[{key:'hints',type:'toggle',label:'Show interaction hints'}],values:{hints:true},defaults:{hints:true}}]});
      if(scene === 'interactions'){
        send('interaction:update',{items:[{id:'garage',key:'E',label:'Open garage',priority:10},{id:'lock',key:'L',label:'Lock vehicle',priority:5}]});
      }
      window.__demoReady=true;
    },150);
  });
  window.prepareCapture = () => {
    const settled=document.createElement('style');settled.textContent='*,*::before,*::after{animation:none!important;transition:none!important}.cortex-settings-tabs{scrollbar-width:none!important}';document.head.append(settled);
    const scene=window.__demoScene;
    const selector={notifications:'#notify-container',menus:'.cortex-menu-root',radial:'.cortex-radial-svg',dialogs:'.cortex-context-dialog',settings:'.cortex-settings-panel',interactions:'.cortex-interactions'}[scene];
    let target=document.querySelector(selector);
    if(!target) return {error:'Missing capture target',selector,classes:[...document.querySelectorAll('#root *')].map(e=>e.className).filter(x=>typeof x==='string').slice(-35)};
    const rect=target.getBoundingClientRect();
    if(scene==='settings'){
      window.__captureBounds={left:Math.floor(rect.left),top:Math.floor(rect.top),width:Math.floor(rect.width),height:Math.floor(rect.height)};
      return window.__captureBounds;
    }
    const scale=Math.min(1100/rect.width,850/rect.height,scene==='interactions'?6:3);
    const holder=document.createElement('div');holder.style.cssText='position:fixed;left:60px;top:60px;width:'+rect.width+'px;height:'+rect.height+'px;transform:scale('+scale+');transform-origin:top left';
    // A capture-only wrapper changes placement and scale; product markup/styles are unchanged.
    target.parentNode.insertBefore(holder,target);holder.append(target);
    target.style.setProperty('position','relative','important');
    for(const p of ['left','top','right','bottom'])target.style.setProperty(p,p==='left'||p==='top'?'0':'auto','important');
    target.style.setProperty('transform','none','important');
    target.style.setProperty('margin','0','important');
    window.__captureBounds={left:60,top:60,width:Math.ceil(rect.width*scale),height:Math.ceil(rect.height*scale)};
    return window.__captureBounds;
  };
})();
